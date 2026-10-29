# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Crap4Ruby
  # Formats analysis results and atomically replaces the project snapshot.
  module Report
    # Ranks known scores first, from highest to lowest.
    # Ties use namespace, method name, then source path in ascending order.
    #
    # @param entries [Array<Entry>] unsorted results
    # @return [Array<Entry>] new sorted array, without modifying the input
    def self.sorted(entries)
      entries.sort_by { |entry| [entry.crap ? 0 : 1, -(entry.crap || 0), entry.namespace, entry.name, entry.path] }
    end

    # Formats a terminal table, preserving entry order and displaying unknown values as N/A.
    #
    # @param entries [Array<Entry>] results in display order
    # @return [String] table with one decimal place for percentages and scores, ending with a newline
    def self.table(entries)
      rows = [["Function", "Namespace", "CC", "Cov%", "CRAP"]] + entries.map do |entry|
        [label(entry.name), label(entry.namespace), entry.complexity.to_s,
          entry.coverage ? format("%.1f%%", entry.coverage) : "N/A",
          entry.crap ? format("%.1f", entry.crap) : "N/A"]
      end
      widths = rows.transpose.map { |column| column.map(&:length).max }
      template = "%-#{widths[0]}s  %-#{widths[1]}s  %#{widths[2]}s  %#{widths[3]}s  %#{widths[4]}s"
      lines = rows.map { |row| format(template, *row) }
      lines.insert(1, "-" * lines.first.length)
      "#{(["CRAP Report", "==========="] + lines).join("\n")}\n"
    end

    # Keeps names with control characters on one terminal line.
    #
    # @param value [String] method name, namespace, or diagnostic label
    # @return [String] original text, or a quoted JSON string when escaping is needed
    def self.label(value)
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
