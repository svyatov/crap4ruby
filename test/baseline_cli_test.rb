# frozen_string_literal: true

require_relative "test_helper"
require "stringio"

class BaselineCLITest < Minitest::Test
  REVISION = "a" * 40

  def setup
    @root = Dir.mktmpdir("crap4ruby-baseline")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write(relative, content)
    path = File.join(@root, relative)
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
    path
  end

  def cli(*args)
    @out = StringIO.new
    @err = StringIO.new
    Crap4Ruby::CLI.new(stdout: @out, stderr: @err).run(args)
  end

  def export(*args)
    cli("--root", @root, "--json-report", "--revision", REVISION, "--no-save", *args)
  end

  def test_exports_complete_exact_scores_and_distinguishes_method_kind
    write("lib/sample.rb", <<~RUBY)
      class Sample
        define_method("self.pick") do |x|
          x ||= 1
          x
        end
        def self.pick = 1
      end
    RUBY
    write("coverage/.resultset.json", '{"Test":{"coverage":{"lib/sample.rb":[1,1,1,0,null,1,null]}}}')

    assert_equal 0, export("--source-root", "./lib"), @err.string
    assert_match(/"schema_version":\s*1/, @out.string)
    assert_match(%r{"crap":\s*"5/2"}, @out.string)
    report = Crap4Ruby::BaselineReport.load(write("report.json", @out.string))

    assert_equal REVISION, report.revision
    assert_equal ["lib"], report.source_roots
    assert_equal "coverage/.resultset.json", report.coverage_path
    actual = report.entries.map { |entry| [entry.kind, entry.name, entry.crap, entry.line] }

    assert_equal [
      ["instance", "self.pick", Rational(5, 2), 2],
      ["singleton", "pick", nil, 6]
    ], actual
    refute_path_exists File.join(@root, ".metrics")
  end

  def test_export_keeps_absolute_threshold_enforcement_and_empty_scope
    assert_equal 0, export, @err.string
    assert_empty Crap4Ruby::BaselineReport.load(write("empty.json", @out.string)).entries

    write("sample.rb", "def pick(x)\n x ? 1 : 0\nend\n")
    write("coverage/.resultset.json", '{"Test":{"coverage":{"sample.rb":[1,0,null]}}}')

    assert_equal 2, export("--threshold", "5"), @err.string
    assert_match(%r{"crap":\s*"6/1"}, @out.string)
    assert_includes @err.string, "CRAP threshold exceeded"
  end

  def test_rejects_incompatible_command_modes
    assert_equal 1, export("--changed")
    assert_empty @out.string
    assert_equal 1, export("--source-root", "missing")
    assert_empty @out.string
    assert_equal 1, cli("--compare", "--base-report", "base.json", "--head-report", "head.json",
      "--coverage", "coverage/.resultset.json")
    assert_empty @out.string
    assert_match(/scan|compare/i, @err.string)
    assert_equal 1, cli("--limit", "10", "--no-coverage")
    assert_empty @out.string
    assert_equal 1, cli("--json-report")
    assert_includes @err.string, "--revision"
    assert_equal 1, cli("--revision", REVISION)
    assert_includes @err.string, "--json-report"
    assert_equal 1, cli("--compare")
    assert_includes @err.string, "--base-report"
  end

  def test_read_only_compare_uses_the_same_verdict_for_reporting_and_gating
    write("sample.rb", "def pick(x)\n x ? 1 : 0\nend\n")
    write("coverage/.resultset.json", '{"Test":{"coverage":{"sample.rb":[1,1,null]}}}')

    assert_equal 0, export, @err.string
    base = write("base.json", @out.string)
    write("coverage/.resultset.json", '{"Test":{"coverage":{"sample.rb":[1,0,null]}}}')

    assert_equal 0, export, @err.string
    head = write("head.json", @out.string)
    flags = ["--compare", "--base-report", base, "--head-report", head, "--limit", "5"]

    assert_equal 0, cli(*flags), @err.string
    assert_includes @out.string, "pick"
    assert_equal 2, cli(*flags, "--fail-on-regression"), @err.string
    assert_includes @out.string, "pick"
    assert_empty @err.string
    assert_equal 1, cli(*flags, "--limit", "NaN")
    assert_empty @out.string
    refute_path_exists File.join(@root, ".metrics")
  end

  def test_uncertainty_and_invalid_report_have_distinct_output
    write("sample.rb", "def pick(x)\n x ? 1 : 0\nend\n")
    write("coverage/.resultset.json", '{"Test":{"coverage":{"sample.rb":[1,1,null]}}}')

    assert_equal 0, export, @err.string
    base = write("base.json", @out.string)
    write("sample.rb", "def pick(x) = x ? 1 : 0\n")

    assert_equal 0, export, @err.string
    head = write("head.json", @out.string)
    flags = ["--compare", "--base-report", base, "--head-report", head, "--limit", "5", "--fail-on-regression"]

    assert_equal 1, cli(*flags), @err.string
    assert_includes @out.string, "pick"
    assert_empty @err.string

    write("head.json", "{}")

    assert_equal 1, cli(*flags)
    assert_empty @out.string
    refute_empty @err.string
  end
end
