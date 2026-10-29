# frozen_string_literal: true

require "json"

module Crap4Ruby
  # Merges SimpleCov line coverage across named test suites.
  class Coverage
    # Reads a SimpleCov resultset, accepting legacy arrays and line-coverage objects.
    #
    # @param path [String] JSON resultset path, relative to the working directory or absolute
    # @param root [String] base directory for source paths inside the report
    # @return [Coverage] merged coverage
    # @raise [Error] if the report cannot be read, parsed, or validated
    def self.load(path, root:)
      new(JSON.parse(File.read(path)), root: root)
    rescue SystemCallError => error
      raise Error,
        "#{path}: cannot read coverage report; generate SimpleCov coverage or use --no-coverage (#{error.message})"
    rescue JSON::ParserError, Error => error
      raise Error, "#{path}: invalid SimpleCov report (#{error.message})"
    end

    # Validates and merges suite reports by the maximum hit count for each line.
    #
    # @param suites [Hash{String => Hash}] parsed resultset keyed by suite name
    # @param root [String] base directory for relative source paths
    # @raise [Error] if suites or line coverage are malformed
    def initialize(suites, root:)
      raise Error, "expected named test suites" unless suites.is_a?(Hash) && !suites.empty?

      @files = {}
      suites.each_value { |suite| add_suite(suite, root) }
    end

    # Measures executable body lines with positive hit counts.
    # Null and out-of-range lines do not enter the denominator.
    #
    # @param method [MethodInfo] method whose path and body lines select coverage
    # @return [Rational, nil] exact fraction from 0 to 1; zero for an absent file,
    #   or nil when body lines are ambiguous or no reported lines are measurable
    def fraction(method)
      body = method.lines
      return nil unless body

      path = File.expand_path(method.path)
      path = File.realpath(path) if File.exist?(path)
      # @type var lines: Array[Integer?]?
      lines = @files[path]
      return Rational(0) unless lines

      hits = body.filter_map { |line| lines[line - 1] }
      return nil if hits.empty?

      Rational(hits.count(&:positive?), hits.size)
    end

    private

    def add_suite(suite, root)
      raise Error, "expected a coverage object for each suite" unless suite.is_a?(Hash) && suite["coverage"].is_a?(Hash)

      suite["coverage"].each { |path, data| add_file(path, data, root) }
    end

    # Normalizes a source path and merges line counts across suites.
    #
    # @param path [String] source path from a suite report
    # @param data [Array<Integer, nil>, Hash] legacy counts or an object with a `lines` array
    # @param root [String] base directory for relative source paths
    # @return [void]
    # @raise [Error] if line counts are invalid
    def add_file(path, data, root)
      key = File.expand_path(path, root)
      key = File.realpath(key) if File.exist?(key)
      lines = data.is_a?(Hash) ? data["lines"] : data
      unless lines.is_a?(Array) && lines.all? { |hit| hit.nil? || (hit.is_a?(Integer) && hit >= 0) }
        raise Error, "#{path}: expected nonnegative line counts or null"
      end

      # Every element was validated above; Steep cannot narrow an array through all?.
      lines = lines #: Array[Integer?]
      # @type var previous: Array[Integer?]?
      previous = @files[key]
      return @files[key] = lines.dup unless previous

      @files[key] = Array.new([previous.size, lines.size].max) do |index|
        [previous[index], lines[index]].compact.max
      end
    end
  end
end
