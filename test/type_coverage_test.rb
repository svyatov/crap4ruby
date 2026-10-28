# frozen_string_literal: true

require_relative "test_helper"
require_relative "../script/type_coverage"

class TypeCoverageTest < Minitest::Test
  def stats(*rows)
    CSV.generate do |csv|
      csv << TypeCoverage::HEADER
      rows.each { |row| csv << ["library", "lib/example.rb", *row] }
    end
  end

  def test_accepts_fully_typed_files_including_files_without_calls
    [0, 12].each do |count|
      assert_empty TypeCoverage.failures(stats(["success", count, 0, count, 100]), ["lib/example.rb"])
    end
  end

  def test_rejects_untyped_failed_and_partially_typed_files
    [["success", 99, 1, 100, 99], ["success", 999, 0, 1000, 100],
      ["error", 0, 0, 0, 0]].each do |row|
      refute_empty TypeCoverage.failures(stats(row), ["lib/example.rb"])
    end
  end

  def test_rejects_missing_extra_and_duplicate_files
    row = ["success", 1, 0, 1, 100]

    refute_empty TypeCoverage.failures(stats, ["lib/example.rb"])
    refute_empty TypeCoverage.failures(stats(row), [])
    refute_empty TypeCoverage.failures(stats(row, row), ["lib/example.rb"])
  end

  def test_rejects_invalid_stats_output
    assert_raises(ArgumentError) { TypeCoverage.failures("", []) }
    assert_raises(ArgumentError) { TypeCoverage.failures(stats(["success", "invalid", 0, 1, 100]), ["lib/example.rb"]) }
  end
end
