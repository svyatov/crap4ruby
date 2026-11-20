# frozen_string_literal: true

require_relative "test_helper"

class BaselineComparisonTest < Minitest::Test
  def entry(name = "calculate", path: "service.rb", line: 1, kind: "instance", complexity: 8,
            score: 32r, coverage: 28.0, note: nil, namespace: "Service")
    Crap4Ruby::BaselineEntry.new(path, line, namespace, kind, name, complexity, coverage, score, note)
  end

  def compare(base, head, limit: 30r, min_increase: 1r)
    base_report = report("a" * 40, base)
    head_report = report("b" * 40, head)
    Crap4Ruby::BaselineComparison.call(base_report, head_report, limit: limit, min_increase: min_increase)
  end

  def report(revision, entries)
    rows = entries.map do |definition|
      {path: definition.path, line: definition.line, namespace: definition.namespace, kind: definition.kind,
       name: definition.name, complexity: definition.complexity, coverage: definition.coverage,
       crap: definition.crap&.to_s, coverage_note: definition.coverage_note}
    end
    Dir.mktmpdir do |directory|
      path = File.join(directory, "report.json")
      File.write(path, JSON.generate({schema_version: 1, revision: revision, tool_version: "0.2.4",
        prism_version: "2.0.1", source_roots: ["."], coverage_path: "coverage.json", entries: rows}))
      Crap4Ruby::BaselineReport.load(path)
    end
  end

  def markdown(result, enforced: true)
    Crap4Ruby::BaselineComparison.markdown(result, enforced: enforced)
  end

  def test_line_shifts_do_not_create_additions_and_an_exact_material_increase_fails
    result = compare([entry(score: 30r)], [entry(line: 19, score: 31.0000000000000000001r)])

    assert_equal 2, result.status
    assert_includes markdown(result), "service.rb:1 → service.rb:19"
    assert_includes markdown(result), "30 → 31.00 (+1.00)"
    assert_includes markdown(result), "Additions: 0"
  end

  def test_limit_and_increase_are_exclusive
    base = [entry("at_limit", score: 28r), entry("at_increase", score: 30r)]
    head = [entry("at_limit", score: 30r), entry("at_increase", score: 31r)]

    assert_equal 0, compare(base, head).status
  end

  def test_same_path_matches_first_then_reports_a_unique_move_with_its_score_change
    base = [entry(path: "a.rb", score: 40r), entry(path: "b.rb", score: 30r)]
    head = [entry(path: "a.rb", score: 40r), entry(path: "c.rb", score: 32r)]
    result = compare(base, head)

    assert_equal 2, result.status
    assert_match(/Moved.*b.rb:1 → c.rb:1/, markdown(result))
  end

  def test_rename_or_kind_change_counts_as_a_removal_and_an_addition
    base = [entry("self.calculate"), entry("rename", namespace: "Old")]
    head = [entry(kind: "singleton"), entry("renamed", namespace: "New")]
    result = compare(base, head)

    assert_equal 2, result.status
    assert_includes markdown(result), "Additions: 2"
    assert_includes markdown(result), "removals: 2"
  end

  def test_lost_and_new_measurements_use_the_head_complexity_to_bound_risk
    unknown = entry(score: nil, coverage: nil, note: "shared_declaration", complexity: 6)
    measured = entry(complexity: 5, score: 28r)

    assert_equal 1, compare([measured], [unknown]).status
    assert_equal 1, compare([], [unknown]).status
    assert_equal 0, compare([measured], [unknown.with(complexity: 5)]).status
    assert_equal 0, compare([], [unknown.with(complexity: 5)]).status
    assert_includes markdown(compare([measured], [unknown])), "upper bound 42"
    assert_includes markdown(compare([measured], [unknown])), "body shares declaration line"
  end

  def test_a_missing_baseline_is_visible_and_does_not_fail_by_itself
    base = [entry(score: nil, coverage: nil, note: "shared_declaration")]
    result = compare(base, [entry])

    assert_equal 0, result.status
    assert_includes markdown(result), "unavailable comparisons: 1"
    assert_equal 0, compare(base, base).status
  end

  def test_a_measured_violation_takes_precedence_over_uncertainty_in_both_modes
    result = compare([], [entry, entry("unknown", score: nil, coverage: nil, note: "shared_declaration")])

    assert_equal 2, result.status
    assert_includes markdown(result), "measured violations"
    assert_includes markdown(result, enforced: false), "report only"
  end

  def test_reordered_ambiguous_definitions_with_new_lines_are_unchanged
    base = [entry(line: 2, score: 32r), entry(line: 10, score: 42r)]
    head = [entry(line: 20, score: 42r), entry(line: 40, score: 32r)]
    result = compare(base, head)

    assert_equal 0, result.status
    assert_includes markdown(result), "Ambiguous group unchanged"
    assert_includes markdown(result), "service.rb:20"
  end

  def test_ambiguous_group_measurements_include_coverage_reason_even_when_scores_are_unchanged
    unknown = entry(score: nil, coverage: nil, note: "shared_declaration")
    base = [entry(line: 2), unknown]
    head = [entry(line: 2), unknown.with(coverage_note: "no_measurable_lines")]
    result = compare(base, head)

    assert_equal 1, result.status
    assert_includes markdown(result), "Ambiguous group changed"
    assert_includes markdown(result), "no measurable lines in report"
  end

  def test_markdown_explains_when_measured_zero_coverage_changes_reason
    absent = entry(line: 2, complexity: 7, score: 56r, coverage: 0.0, note: "absent_file")
    other = absent.with(line: 21, coverage_note: nil)
    result = compare([absent, other], [absent.with(coverage_note: nil), other])

    assert_equal 1, result.status
    assert_includes markdown(result), "0.0% (file absent from report)"
  end

  def test_only_the_current_members_of_a_changed_ambiguous_group_set_uncertainty
    base = [entry(line: 2, score: 40r), entry(line: 10, score: 42r)]
    head = [entry(line: 2, score: 27r), entry(line: 10, score: 30r)]

    assert_equal 0, compare(base, head).status
    assert_equal 1, compare(head, base).status
  end

  def test_ambiguous_group_matching_keeps_multiplicity_and_path_changes
    old = entry(line: 2)
    base = [old, old.with(line: 3)]
    moved = old.with(path: "new.rb")

    assert_equal 1, compare(base, [old]).status
    assert_equal 1, compare(base, [old, moved]).status
    assert_equal 2, compare([], base).status
  end

  def test_existing_high_scores_are_bounded_and_include_improvements
    base = Array.new(30) { |number| entry("method#{number}", score: 45r + number, complexity: 9) }
    head = base.map { |definition| definition.with(crap: 37r) }
    result = compare(base, head)
    text = markdown(result)

    assert_equal 0, result.status
    assert_includes text, "improvements: 30"
    assert_includes text, "<details>"
    assert_match(/\d+ of 30 shown/, text)
  end

  def test_markdown_keeps_untrusted_text_literal_and_on_one_line
    result = compare([], [entry("x|`<tag>\n", path: "bad|name.rb", namespace: "[link](https://example.com)")])
    text = markdown(result)

    assert_includes text, "&#124;"
    assert_includes text, "&#60;tag&#62;"
    assert_includes text, "u000a"
    refute_includes text, "[link](https://example.com)"
    refute_includes text, "<tag>"
  end

  def test_markdown_reports_omitted_actionable_findings_and_group_members
    old = Array.new(7) { |number| entry("duplicate", line: number + 1) }
    new_methods = Array.new(60) { |number| entry("method#{number}", score: 2r, complexity: 2) }
    result = compare(old, [*old, *new_methods])
    text = markdown(result)

    assert_includes text, "Additions: 60"
    assert_includes text, "11 more findings omitted"
    assert_includes text, "Head (5 of 7 shown)"
  end
end
