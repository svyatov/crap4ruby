# frozen_string_literal: true

require "fileutils"
require "pathname"
require "tempfile"

module Crap4Ruby
  # Formats analysis results and atomically replaces the project snapshot.
  module Report
    # Coverage column text for exceptional results.
    COVERAGE_NOTES = {
      shared_declaration: "body shares declaration line",
      shared_trailing_code: "trailing code shares body line",
      no_measurable_lines: "no measurable lines in report",
      absent_file: "file absent from report"
    }.freeze

    # Ranks known scores first, from highest to lowest.
    # Ties use namespace, method name, then source path in ascending order.
    #
    # @param entries [Array<Entry>] unsorted results
    # @return [Array<Entry>] new sorted array, without modifying the input
    def self.sorted(entries)
      entries.sort_by { |entry| [entry.crap ? 0 : 1, -(entry.crap || 0), entry.namespace, entry.name, entry.path] }
    end

    # Formats methods above the display limit and methods with unknown scores.
    # Verbose output includes every entry, preserving the complete table format.
    #
    # @param entries [Array<Entry>] results in display order
    # @param root [String] analysis root for displayed paths
    # @param files [Integer] number of source files analyzed
    # @param coverage_source [String, false, nil] resultset path, false when disabled, or nil for an empty selection
    # @param threshold [Integer, Float, Rational] exclusive display limit
    # @param limit [String, nil] display label for the threshold
    # @param verbose [Boolean] whether to show all entries
    # @return [String] scan summary followed by a table or empty-result message
    def self.terminal(entries, root:, files:, coverage_source:, threshold: 30, limit: nil, verbose: false)
      above = entries.select { |entry| entry.crap && entry.crap > threshold }
      unknown = entries.select { |entry| entry.crap.nil? }
      limit ||= threshold.to_f.to_s.delete_suffix(".0")
      scanned = "Scanned #{quantity(files, "file")}, #{quantity(entries.size, "method")}."
      counts = "#{above.size} above CRAP #{limit}, #{unknown.size} unknown."
      summary = "#{scanned} #{counts}\n#{coverage_summary(coverage_source, root)}\n"
      visible = terminal_entries(entries, above + unknown, coverage_source, verbose)
      summary + terminal_body(visible, entries.empty?, limit, root, verbose)
    end

    # Formats a terminal table, preserving entry order and displaying unknown values as N/A.
    #
    # @param entries [Array<Entry>] results in display order
    # @param root [String] analysis root for displayed paths
    # @return [String] table with one decimal place for percentages and scores, ending with a newline
    def self.table(entries, root:)
      rows = [["Function", "Namespace", "CC", "Cov%", "CRAP", "Location"]] + entries.map do |entry|
        [label(entry.name), label(entry.namespace), entry.complexity.to_s,
          coverage_cell(entry), entry.crap ? format("%.1f", entry.crap) : "N/A",
          label("#{relative_path(entry.path, root)}:#{entry.line}")]
      end
      widths = rows.transpose.map { |column| column.map(&:length).max }
      template = "%-#{widths[0]}s  %-#{widths[1]}s  %#{widths[2]}s  %-#{widths[3]}s  %#{widths[4]}s  %s"
      lines = rows.map { |row| format(template, *row) }
      lines.insert(1, "-" * lines.first.length)
      "#{(["CRAP Report", "==========="] + lines).join("\n")}\n"
    end

    def self.terminal_entries(entries, filtered, coverage_source, verbose)
      case coverage_source
      when false then entries.each_with_index.sort_by { |(entry, index)| [-entry.complexity, index] }.map(&:first)
      else verbose ? entries : filtered
      end
    end

    def self.terminal_body(entries, empty, limit, root, verbose)
      return table(entries, root: root) if verbose || !entries.empty?

      empty ? "No methods found.\n" : "No methods exceed CRAP #{limit}.\n"
    end

    def self.coverage_summary(source, root)
      case source
      when String then "Coverage: #{label(relative_path(source, root))}"
      when false then "Coverage disabled"
      else "Coverage not read: no source files."
      end
    end

    def self.coverage_cell(entry)
      value = entry.coverage ? format("%.1f%%", entry.coverage) : "N/A"
      note = entry.coverage_note
      note ? "#{value} (#{COVERAGE_NOTES.fetch(note)})" : value
    end

    def self.quantity(count, noun)
      "#{count} #{noun}#{"s" unless count == 1}"
    end

    def self.relative_path(path, root)
      absolute = File.expand_path(path, root)
      relative = Pathname.new(absolute.b).relative_path_from(Pathname.new(root.b)).to_s
      relative.force_encoding(absolute.encoding)
    end

    private_class_method :terminal_entries, :terminal_body, :coverage_summary, :coverage_cell, :quantity, :relative_path

    # Keeps names with control characters on one terminal line.
    #
    # @param value [String] method name, namespace, or diagnostic label
    # @return [String] original text or a quoted representation
    def self.label(value)
      return value.dump unless value.valid_encoding?

      value.match?(/[[:cntrl:]]/) ? JSON.generate(value) : value
    end

    # Serializes the crapper-compatible snapshot, preserving entry order.
    # Source paths are omitted; unknown numeric values become EDN nil.
    #
    # @param entries [Array<Entry>] results in snapshot order
    # @return [String] EDN map containing entries, ending with a newline
    def self.edn(entries)
      rows = entries.map do |entry|
        "  {:name #{JSON.generate(entry.name)}, :namespace #{JSON.generate(entry.namespace)}, " \
          ":complexity #{entry.complexity}, :coverage #{number(entry.coverage)}, :crap #{number(entry.crap)}}"
      end
      rows.empty? ? "{:entries []}\n" : "{:entries [\n#{rows.join("\n")}\n]}\n"
    end

    # Formats an EDN number with at most four decimal places and at least one.
    #
    # @param value [Float, Rational, nil] percentage or CRAP score
    # @return [String] decimal representation, or `nil` for an unknown value
    def self.number(value)
      return "nil" if value.nil?

      text = format("%.4f", value)
      text.sub!(/0+\z/, "")
      text.end_with?(".") ? "#{text}0" : text
    end

    # Atomically replaces `.metrics/crap.edn`, creating the directory if necessary.
    # An empty selection replaces the snapshot with an empty entries vector.
    #
    # @param entries [Array<Entry>] results in snapshot order
    # @param root [String] project directory that receives the snapshot
    # @return [String] snapshot path
    # @raise [SystemCallError, IOError] if the snapshot cannot be written or replaced
    def self.write(entries, root:)
      directory = File.join(root, ".metrics")
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "crap.edn")
      Tempfile.create(["crap", ".edn"], directory) do |file|
        file.write(edn(entries))
        file.close
        File.rename(file.path, path)
      end
      path
    end
  end
end
