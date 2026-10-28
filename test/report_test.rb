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
    assert_equal "{:entries [\n  {:name \"quoted\\\"\\\\\\n\\t\", :namespace \"Sample\", :complexity 2, :coverage 50.0, :crap 2.3457}\n]}\n", text
  end
end
