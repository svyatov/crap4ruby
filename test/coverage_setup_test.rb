# frozen_string_literal: true

require_relative "test_helper"
require "coverage"

class CoverageSetupTest < Minitest::Test
  def test_collects_coverage_while_tests_execute
    assert ::Coverage.running?, "test_helper must start SimpleCov before loading application code"
  end
end
