# frozen_string_literal: true

require "json"

module Crap4Ruby
  class Coverage
    def self.load(path, root:)
      new(JSON.parse(File.read(path)), root: root)
    rescue SystemCallError => error
      raise Error, "#{path}: cannot read coverage report; generate SimpleCov coverage or use --no-coverage (#{error.message})"
    rescue JSON::ParserError, Error => error
      raise Error, "#{path}: invalid SimpleCov report (#{error.message})"
    end

    def initialize(suites, root:)
      raise Error, "expected named test suites" unless suites.is_a?(Hash) && !suites.empty?

      @files = {}
      suites.each_value { |suite| add_suite(suite, root) }
    end

    def fraction(method)
      path = File.expand_path(method.path)
      path = File.realpath(path) if File.exist?(path)
      lines = @files[path]
      return 0.0 unless lines

      hits = method.lines.filter_map { |line| lines[line - 1] }
      return nil if hits.empty?

      hits.count(&:positive?).fdiv(hits.size)
    end

    private

    def add_suite(suite, root)
      unless suite.is_a?(Hash) && suite["coverage"].is_a?(Hash)
        raise Error, "expected a coverage object for each suite"
      end
      suite["coverage"].each { |path, data| add_file(path, data, root) }
    end

    def add_file(path, data, root)
      key = File.expand_path(path, root)
      key = File.realpath(key) if File.exist?(key)
      lines = data.is_a?(Hash) ? data["lines"] : data
      unless lines.is_a?(Array) && lines.all? { |hit| hit.nil? || (hit.is_a?(Integer) && hit >= 0) }
        raise Error, "#{path}: expected nonnegative line counts or null"
      end
      previous = @files[key] || []
      @files[key] = Array.new([previous.size, lines.size].max) do |index|
        [previous[index], lines[index]].compact.max
      end
    end
  end
end
