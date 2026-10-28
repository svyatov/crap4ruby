# frozen_string_literal: true

require "prism"
require_relative "crap4ruby/version"

module Crap4Ruby
  Error = Class.new(StandardError)
  MethodInfo = Data.define(:name, :namespace, :complexity, :lines, :path)
end

require_relative "crap4ruby/analyzer"
