# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  root File.expand_path("..", File.dirname(__FILE__))
  command_name "crap4ruby tests"
  cover "lib/**/*.rb"
end

require "minitest/autorun"
require "tmpdir"
require "fileutils"
require_relative "../lib/crap4ruby"
