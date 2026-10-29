# frozen_string_literal: true

require "prism"
require_relative "crap4ruby/version"

# Static method analysis, coverage, and CRAP reporting for the CLI.
# These Ruby interfaces are maintainer APIs, outside the compatibility policy.
#
# @api private
module Crap4Ruby
  # Invalid source, coverage, command options, or external command results.
  class Error < StandardError
  end

  # Immutable static analysis of one method definition.
  MethodInfo = Data.define(:name, :namespace, :complexity, :lines, :path)

  # Immutable analysis result with coverage and a CRAP score.
  Entry = Data.define(:name, :namespace, :complexity, :coverage, :crap, :path)

  # @!parse
  #   class Crap4Ruby::MethodInfo
  #     # @return [String] method name, prefixed with `self.` for singleton methods
  #     attr_reader :name
  #     # @return [String] lexical owner, or `Object` for a top-level method
  #     attr_reader :namespace
  #     # @return [Integer] cyclomatic complexity of the body
  #     attr_reader :complexity
  #     # @return [Array<Integer>, nil] one-based body lines, or nil when disabled or ambiguous
  #     attr_reader :lines
  #     # @return [String] source path supplied to the analyzer
  #     attr_reader :path
  #   end
  #   class Crap4Ruby::Entry
  #     # @return [String] method name, prefixed with `self.` for singleton methods
  #     attr_reader :name
  #     # @return [String] lexical owner, or `Object` for a top-level method
  #     attr_reader :namespace
  #     # @return [Integer] cyclomatic complexity
  #     attr_reader :complexity
  #     # @return [Float, nil] percentage from 0 to 100, or nil when unmeasurable or disabled
  #     attr_reader :coverage
  #     # @return [Rational, Float, nil] CRAP score, or nil when coverage is unknown
  #     attr_reader :crap
  #     # @return [String] source path supplied to the analyzer
  #     attr_reader :path
  #   end
end

require_relative "crap4ruby/analyzer"
require_relative "crap4ruby/coverage"
require_relative "crap4ruby/score"
require_relative "crap4ruby/report"
require_relative "crap4ruby/discovery"
require_relative "crap4ruby/cli"
