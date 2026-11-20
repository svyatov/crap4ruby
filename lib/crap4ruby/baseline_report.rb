# frozen_string_literal: true

require "json"

module Crap4Ruby
  # A method definition and its measurements in a baseline report.
  BaselineEntry = Data.define(:path, :line, :namespace, :kind, :name, :complexity, :coverage, :crap, :coverage_note)

  # @!parse
  #   class Crap4Ruby::BaselineEntry
  #     # @return [String] source path relative to the analysis root
  #     attr_reader :path
  #     # @return [Integer] one-based declaration line
  #     attr_reader :line
  #     # @return [String] lexical method owner
  #     attr_reader :namespace
  #     # @return [String] instance or singleton method kind
  #     attr_reader :kind
  #     # @return [String] literal method name without any singleton prefix
  #     attr_reader :name
  #     # @return [Integer] cyclomatic complexity
  #     attr_reader :complexity
  #     # @return [Float, nil] percentage from 0 to 100, or nil when unmeasurable
  #     attr_reader :coverage
  #     # @return [Rational, nil] exact CRAP score, or nil when unmeasurable
  #     attr_reader :crap
  #     # @return [String, nil] reason for exceptional coverage
  #     attr_reader :coverage_note
  #   end

  # Validated method results for one revision and one source scope.
  class BaselineReport
    SCHEMA_VERSION = 1
    REPORT_FIELDS = %w[coverage_path entries prism_version revision schema_version source_roots tool_version].freeze
    ENTRY_FIELDS = %w[complexity coverage coverage_note crap kind line name namespace path].freeze
    REVISION = /\A(?:[0-9a-fA-F]{40}|[0-9a-fA-F]{64})\z/
    SCORE = %r{\A[1-9][0-9]*/[1-9][0-9]*\z}

    # Reject duplicate members on all supported versions of Ruby's JSON parser.
    # @api private
    class UniqueObject < Hash
      # Stores a member unless an earlier member already used the same key.
      #
      # @param key [String] JSON object member name
      # @param value [Object] parsed JSON value
      # @return [Object] stored value
      # @raise [Error] if the member name repeats
      def []=(key, value)
        raise Error, "duplicate field #{key.dump}" if key?(key)

        super
      end
    end
    private_constant :UniqueObject

    # @return [String] full Git object ID supplied by the caller
    attr_reader :revision

    # @return [String] crap4ruby version that generated the report
    attr_reader :tool_version

    # @return [String] Prism version used for the scan
    attr_reader :prism_version

    # @return [Array<String>] sorted, unique project-relative source roots
    attr_reader :source_roots

    # @return [String, nil] SimpleCov resultset path, or nil when it was not read
    attr_reader :coverage_path

    # @return [Array<BaselineEntry>] one entry per method definition
    attr_reader :entries

    # Holds validated report metadata and definitions.
    #
    # @param revision [String] full Git object ID
    # @param tool_version [String] crap4ruby version
    # @param prism_version [String] Prism version
    # @param source_roots [Array<String>] canonical source directories
    # @param coverage_path [String, nil] SimpleCov resultset path
    # @param entries [Array<BaselineEntry>] validated definitions
    def initialize(revision, tool_version, prism_version, source_roots, coverage_path, entries)
      @revision = revision
      @tool_version = tool_version
      @prism_version = prism_version
      @source_roots = source_roots
      @coverage_path = coverage_path
      @entries = entries
    end
    private_class_method :new # @dynamic revision, tool_version, prism_version, source_roots, coverage_path, entries

    # Resolves and sorts source directories relative to the real analysis root.
    #
    # @param root [String] analysis directory
    # @param roots [Array<String>] relative directories, or empty for the default scan
    # @return [Array<String>] sorted unique scope, using "." for the root itself
    # @raise [Error] if a source root is missing, absolute, or outside the analysis root
    def self.scope(root, roots)
      root = File.realpath(root)
      roots = ["."] if roots.empty?
      roots.map { |path| scope_path(root, path) }.uniq.sort
    end

    # Validates selected source paths even when a file has no method definitions.
    #
    # @param root [String] real analysis directory
    # @param files [Array<String>] real paths from source discovery
    # @return [void]
    # @raise [Error] if a path is outside the root or cannot be represented in UTF-8
    def self.validate_files!(root, files)
      root = root.b
      files.each { |path| relative_path(path.b, root, "source file") }
    end

    # Serializes the complete method results in deterministic order.
    #
    # @param entries [Array<Entry>] scored definitions
    # @param root [String] analysis directory
    # @param source_roots [Array<String>] canonical scan scope
    # @param coverage_path [String, nil] SimpleCov resultset path
    # @param revision [String] full Git object ID
    # @return [String] UTF-8 JSON with a final newline
    # @raise [Error] if the results cannot be represented as a version 1 report
    def self.dump(entries, root:, source_roots:, coverage_path:, revision:)
      root = File.realpath(root)
      rows = entries.map { |entry| dump_entry(entry, root) }.sort_by { |row| entry_order(row) }
      document = {
        "schema_version" => SCHEMA_VERSION, "tool_version" => VERSION, "prism_version" => Prism::VERSION,
        "revision" => revision, "source_roots" => source_roots,
        "coverage_path" => coverage_path && utf8_path(coverage_path), "entries" => rows
      }
      parse_report(document)
      "#{JSON.pretty_generate(document)}\n"
    end

    # Reads and validates a version 1 baseline report.
    #
    # @param path [String] report filename
    # @return [BaselineReport] validated results
    # @raise [Error] if the file cannot be read or violates the contract
    def self.load(path)
      text = File.binread(path).force_encoding(Encoding::UTF_8)
      raise Error, "expected UTF-8 JSON" unless text.valid_encoding?

      parse_report(JSON.parse(text, object_class: UniqueObject))
    rescue SystemCallError => error
      raise Error, "#{path}: cannot read baseline report (#{error.message})"
    rescue JSON::ParserError, Error => error
      raise Error, "#{path}: invalid baseline report (#{error.message})"
    end

    # Requires the reports to have identical source scopes and analysis versions.
    #
    # @param base [BaselineReport] report for the comparison base
    # @param head [BaselineReport] report for the comparison head
    # @return [void]
    # @raise [Error] if the reports are incompatible
    def self.check_compatible!(base, head)
      check_field("tool_version", base.tool_version, head.tool_version)
      check_field("prism_version", base.prism_version, head.prism_version)
      check_field("source_roots", base.source_roots, head.source_roots)
    end

    class << self
      private

      def check_field(field, base, head)
        return if base == head

        raise Error, "incomparable reports: #{field} differs (base #{base.inspect}, head #{head.inspect})"
      end

      def scope_path(root, path)
        if path.empty? || File.absolute_path?(path) || path.include?("\0")
          raise Error, "#{path.dump}: source root must be a project-relative directory"
        end

        directory = File.realpath(File.absolute_path(path, root))
        raise Error, "#{path.dump}: source root must be a directory" unless File.directory?(directory)

        directory == root ? "." : relative_path(directory, root, "source root")
      rescue SystemCallError => error
        raise Error, "#{path.dump}: source root must be a directory (#{error.message})"
      end

      def relative_path(path, root, field)
        prefix = File.join(root, "")
        raise Error, "#{path.dump}: #{field} is outside the analysis root #{root.dump}" unless path.start_with?(prefix)

        utf8_path(path.delete_prefix(prefix))
      end

      def utf8_path(path)
        text = path.b.force_encoding(Encoding::UTF_8)
        raise Error, "#{path.dump}: report path must be representable in UTF-8" unless text.valid_encoding?

        text
      end

      def utf8_text(value)
        text = value.encode(Encoding::UTF_8)
        raise EncodingError unless text.valid_encoding?

        text
      end

      def dump_entry(entry, root)
        path = relative_path(File.absolute_path(entry.path.b, root.b), root.b, "entry path")
        kind = entry.singleton ? "singleton" : "instance"
        name = entry.singleton ? entry.name.delete_prefix("self.") : entry.name
        {
          "path" => path, "line" => entry.line, "namespace" => utf8_text(entry.namespace), "kind" => kind,
          "name" => utf8_text(name), "complexity" => entry.complexity, "coverage" => entry.coverage,
          "crap" => entry.crap&.to_r&.to_s, "coverage_note" => entry.coverage_note&.to_s
        }
      rescue EncodingError
        raise Error, "#{entry.path.dump}:#{entry.line}: report method name and namespace must be representable in UTF-8"
      end

      def entry_order(row)
        [row["path"], row["line"], row["namespace"], row["kind"], row["name"], row["complexity"],
          row["coverage"].inspect, row["crap"].to_s, row["coverage_note"].to_s]
      end

      def parse_report(value)
        report = object(value, REPORT_FIELDS)
        version = report["schema_version"]
        unless version.is_a?(Integer) && version == SCHEMA_VERSION
          raise Error, "unsupported schema_version #{version.inspect}; expected #{SCHEMA_VERSION}"
        end

        revision = text_field(report["revision"], "revision")
        raise Error, "revision must be a full 40- or 64-character Git object ID" unless REVISION.match?(revision)

        roots = read_roots(report["source_roots"])
        entries = read_entries(report["entries"], roots)
        coverage_path = read_coverage_path(report["coverage_path"], entries.empty?)
        new(revision, text_field(report["tool_version"], "tool_version"),
          text_field(report["prism_version"], "prism_version"), roots, coverage_path, entries)
      end

      def object(value, fields)
        return value if value.is_a?(Hash) && value.keys.sort == fields

        raise Error, "expected an object with fields #{fields.join(", ")}"
      end

      def text_field(value, field)
        return value if value.is_a?(String) && value.valid_encoding? && !value.empty?

        raise Error, "#{field} must be a nonempty string"
      end

      def read_roots(value)
        raise Error, "source_roots must be a nonempty array" unless value.is_a?(Array) && !value.empty?

        roots = value.map { |path| path == "." ? "." : canonical_path(path, "source_roots") }
        raise Error, "source_roots must be sorted and unique" unless roots == roots.uniq.sort

        roots
      end

      def canonical_path(value, field)
        path = text_field(value, field)
        components = path.split("/", -1)
        if path.include?("\0") || components.intersect?(["", ".", ".."])
          raise Error, "#{field} must be a canonical project-relative path"
        end

        path
      end

      def read_coverage_path(value, empty)
        return if value.nil? && empty

        path = text_field(value, "coverage_path")
        raise Error, "coverage_path cannot contain NUL bytes" if path.include?("\0")

        path
      end

      def read_entries(value, roots)
        raise Error, "entries must be an array" unless value.is_a?(Array)

        value.map.with_index(1) do |entry, index|
          read_entry(object(entry, ENTRY_FIELDS), roots)
        rescue Error => error
          raise Error, "entry #{index}: #{error.message}"
        end
      end

      def read_entry(record, roots)
        path = canonical_path(record["path"], "path")
        unless roots.any? { |root| root == "." || path.start_with?("#{root}/") }
          raise Error, "path is outside source_roots"
        end

        line = positive_integer(record["line"], "line")
        namespace = text_field(record["namespace"], "namespace")
        kind = text_field(record["kind"], "kind")
        raise Error, "kind must be instance or singleton" unless %w[instance singleton].include?(kind)

        name = record["name"]
        raise Error, "name must be a string" unless name.is_a?(String) && name.valid_encoding?

        complexity = positive_integer(record["complexity"], "complexity")
        score, coverage, note = measurement(record, complexity)
        BaselineEntry.new(path, line, namespace, kind, name, complexity, coverage, score, note)
      end

      def positive_integer(value, field)
        return value if value.is_a?(Integer) && value.positive?

        raise Error, "#{field} must be a positive integer"
      end

      def measurement(record, complexity)
        upper = (complexity * complexity) + complexity
        score = read_score(record["crap"], complexity, upper)
        coverage = read_percentage(record["coverage"])
        note = record["coverage_note"]
        if score.nil? && coverage.nil?
          return [nil, nil, note.to_s] if %w[shared_declaration shared_trailing_code no_measurable_lines].include?(note)
        elsif score && coverage
          return [score, coverage, nil] if note.nil?
          return [score, coverage, "absent_file"] if note == "absent_file" && coverage.zero? && score == upper
        end

        raise Error, "coverage_note is unknown or inconsistent with coverage and crap"
      end

      def read_score(value, complexity, upper)
        return if value.nil?

        unless value.is_a?(String) && SCORE.match?(value)
          raise Error, "crap must be a rational string with a positive denominator"
        end

        score = Rational(value)
        raise Error, "crap is outside the range for this complexity" unless score.between?(complexity, upper)

        score
      end

      def read_percentage(value)
        return if value.nil?

        return value.to_f if (value.is_a?(Integer) || value.is_a?(Float)) && value.between?(0, 100)

        raise Error, "coverage must be a number from 0 to 100"
      end
    end
  end
end
