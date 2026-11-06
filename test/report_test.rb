# frozen_string_literal: true

require_relative "test_helper"

class ReportTest < Minitest::Test
  def entry(name, score, path = "sample.rb")
    Crap4Ruby::Entry.new(name, "Sample", 2, score ? 50.0 : nil, score, path)
  end

  def test_orders_scores_before_unknowns_and_breaks_ties_deterministically
    entries = [entry("none", nil), entry("low", 2.5), entry("worst", 6.0), entry("aaa", 6.0)]

    assert_equal %w[aaa worst low none], Crap4Ruby::Report.sorted(entries).map(&:name)
  end

  def test_writes_the_exact_edn_shape_with_escaped_strings_and_precise_scores
    text = Crap4Ruby::Report.edn([entry("quoted\"\\\n\t", 2.34567)])

    assert_equal "{:entries [\n  {:name \"quoted\\\"\\\\\\n\\t\", :namespace \"Sample\", " \
                 ":complexity 2, :coverage 50.0, :crap 2.3457}\n]}\n",
      text
  end

  def test_terminal_shows_only_scores_above_30_and_unknowns_in_entry_order
    entries = [entry("above", 30.01), entry("equal", 30.0), entry("below", 29.0), entry("unknown", nil)]

    text = Crap4Ruby::Report.terminal(entries)

    assert_match(/above\s+Sample\s+2\s+50.0%\s+30.0/, text)
    assert_match(%r{unknown\s+Sample\s+2\s+N/A\s+N/A}, text)
    refute_includes text, "equal"
    refute_includes text, "below"
    assert_match(/above.*unknown/m, text)
  end

  def test_terminal_compares_exact_scores_against_an_explicit_limit
    entries = [entry("above", Rational("2.256")), entry("equal", Rational("2.25599999999999999999")),
      entry("below", Rational("2.2559")), entry("unknown", nil)]

    text = Crap4Ruby::Report.terminal(entries, threshold: Rational("2.25599999999999999999"))

    assert_includes text, "above"
    assert_includes text, "unknown"
    refute_includes text, "equal"
    refute_includes text, "below"
  end

  def test_terminal_distinguishes_empty_analysis_from_filtered_results
    assert_equal "No methods found.\n", Crap4Ruby::Report.terminal([])
    assert_equal "No methods exceed CRAP 30.\n", Crap4Ruby::Report.terminal([entry("low", 2.0)])
    assert_equal "No methods exceed CRAP 2.5.\n",
      Crap4Ruby::Report.terminal([entry("equal", 2.5)], threshold: Rational("2.5"))
  end

  def test_verbose_terminal_preserves_the_complete_table
    entries = [entry("high", 42.0), entry("low", 2.0), entry("unknown", nil)]

    assert_equal Crap4Ruby::Report.table(entries), Crap4Ruby::Report.terminal(entries, verbose: true)
    assert_equal Crap4Ruby::Report.table(entries),
      Crap4Ruby::Report.terminal(entries, threshold: 100, verbose: true)
    assert_equal Crap4Ruby::Report.table([]), Crap4Ruby::Report.terminal([], verbose: true)
  end
end
