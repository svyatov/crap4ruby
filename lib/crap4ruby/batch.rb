# frozen_string_literal: true

module Crap4Ruby
  # Analyzes selected files and scores their methods in input order.
  module Batch
    # Reads Ruby source without executing it and preserves method order per file.
    #
    # @param files [Array<String>] source paths in analysis order
    # @param coverage [Coverage, nil] measured coverage, or nil for complexity only
    # @param jobs [Integer, nil] worker count, or nil for automatic selection
    # @return [Array<Entry>] scored methods in file and traversal order
    # @raise [ArgumentError] if the requested worker count is not positive
    def self.call(files, coverage, jobs: nil)
      raise ArgumentError, "jobs must be positive" if jobs && jobs < 1

      analyzer = Analyzer.new(coverage: !coverage.nil?)
      files.flat_map do |path|
        analyzer.call(File.binread(path), path: path).map { |method| Score.call(method, coverage) }
      end
    end
  end
end
