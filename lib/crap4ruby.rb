# frozen_string_literal: true

require "prism"
require_relative "crap4ruby/version"

module Crap4Ruby
  Error = Class.new(StandardError)
  MethodInfo = Data.define(:name, :namespace, :complexity, :lines, :path)
  Entry = Data.define(:name, :namespace, :complexity, :coverage, :crap, :path)
end

require_relative "crap4ruby/analyzer"
require_relative "crap4ruby/coverage"
require_relative "crap4ruby/score"
require_relative "crap4ruby/report"
require_relative "crap4ruby/discovery"
require_relative "crap4ruby/cli"
