# frozen_string_literal: true

require_relative "test_helper"

class CoverageTest < Minitest::Test
  def in_project
    Dir.mktmpdir("crap4ruby") { |root| yield root, File.join(root, ".resultset.json") }
  end

  def test_scores_only_body_lines_from_simplecov
    in_project do |root, report|
      File.write(report, JSON.generate("RSpec" => {"coverage" => {
        "sample.rb" => {"lines" => [1, 4, nil, 0, nil]}
      }}))
      method = Crap4Ruby::MethodInfo.new("pick", "Sample", 4, [2, 3, 4], File.join(root, "sample.rb"))

      entry = Crap4Ruby::Score.call(method, Crap4Ruby::Coverage.load(report, root: root))

      assert_equal 50.0, entry.coverage
      assert_equal 6.0, entry.crap
    end
  end

  def test_merges_legacy_and_current_suites_by_covered_line_union
    in_project do |root, report|
      absolute = File.join(root, "sample.rb")
      File.write(report, JSON.generate(
        "RSpec" => {"coverage" => {absolute => [1, 1, 0, nil]}},
        "Minitest" => {"coverage" => {"sample.rb" => {"lines" => [1, 0, 3, nil]}}}
      ))
      method = Crap4Ruby::MethodInfo.new("pick", "Sample", 4, [2, 3], absolute)
      entry = Crap4Ruby::Score.call(method, Crap4Ruby::Coverage.load(report, root: root))

      assert_equal 100.0, entry.coverage
      assert_equal 4.0, entry.crap
    end
  end

  def test_distinguishes_missing_methods_unmeasurable_methods_and_disabled_coverage
    in_project do |root, report|
      File.write(report, JSON.generate("RSpec" => {"coverage" => {"empty.rb" => {"lines" => [1, nil]}}}))
      coverage = Crap4Ruby::Coverage.load(report, root: root)
      method = Crap4Ruby::MethodInfo.new("pick", "Sample", 3, [2], File.join(root, "absent.rb"))
      assert_equal [0.0, 12.0], Crap4Ruby::Score.call(method, coverage).then { |entry| [entry.coverage, entry.crap] }
      assert_nil Crap4Ruby::Score.call(method, nil).crap
      empty = method.with(path: File.join(root, "empty.rb"))
      assert_nil Crap4Ruby::Score.call(empty, coverage).coverage
    end
  end

  def test_rejects_missing_and_malformed_reports_with_actionable_errors
    in_project do |root, report|
      error = assert_raises(Crap4Ruby::Error) { Crap4Ruby::Coverage.load(report, root: root) }
      assert_includes error.message, "--no-coverage"
      ["{", "[]", "{}", '{"RSpec":{}}', '{"RSpec":{"coverage":[]}}',
        '{"RSpec":{"coverage":{"a.rb":{"lines":[-1]}}}}',
        '{"RSpec":{"coverage":{"a.rb":{"lines":[true]}}}}'].each do |invalid|
        File.write(report, invalid)
        error = assert_raises(Crap4Ruby::Error) { Crap4Ruby::Coverage.load(report, root: root) }
        assert_includes error.message, report
      end
    end
  end
end
