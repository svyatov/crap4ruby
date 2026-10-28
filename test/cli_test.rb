# frozen_string_literal: true

require_relative "test_helper"
require "stringio"
require "open3"
require "shellwords"

class CLITest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("crap4ruby-cli")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def write(path, content)
    target = File.join(@root, path)
    FileUtils.mkdir_p(File.dirname(target))
    File.write(target, content)
    target
  end

  def run_cli(*arguments)
    @out = StringIO.new
    @err = StringIO.new
    Crap4Ruby::CLI.new(stdout: @out, stderr: @err).run(["--root", @root, *arguments])
  end

  def snapshot
    File.read(File.join(@root, ".metrics/crap.edn"))
  end

  def test_writes_complexity_only_table_and_snapshot
    write("lib/sample.rb", "class Sample\n def pick(x)\n x ? 1 : 0\n end\nend\n")

    assert_equal 0, run_cli("--no-coverage")
    assert_includes @out.string, "CRAP Report"
    assert_match(%r{pick\s+Sample\s+2\s+N/A\s+N/A}, @out.string)
    assert_includes snapshot, ':name "pick"'
    assert_includes snapshot, ":coverage nil, :crap nil"
  end

  def test_reads_coverage_and_compares_unrounded_scores
    write("lib/sample.rb", "class Sample\n def pick(x)\n x ||= 1\n x\n end\nend\n")
    write("results.json", JSON.generate("RSpec" => {"coverage" => {
      "lib/sample.rb" => {"lines" => [1, 1, 1, 0, nil, nil]}
    }}))

    assert_equal 0, run_cli("--coverage", "results.json", "--threshold", "2.5")
    assert_includes snapshot, ":coverage 50.0, :crap 2.5"
    assert_equal 2, run_cli("--coverage", "results.json", "--threshold", "2.49")
    assert_match(/threshold/i, @err.string)
  end

  def test_preserves_decimal_threshold_precision
    write("lib/sample.rb", "def pick(x)\n value = 1\n if x\n value + 1\n else\n value - 1\n value - 2\n end\nend\n")
    write("results.json", JSON.generate("RSpec" => {"coverage" => {
      "lib/sample.rb" => {"lines" => [1, 1, 1, 1, nil, 0, 0, nil, nil]}
    }}))

    assert_equal 2, run_cli("--coverage", "results.json", "--threshold", "2.25599999999999999999")
    assert_equal 0, run_cli("--coverage", "results.json", "--threshold", "2.256")
    assert_equal 0, run_cli("--coverage", "results.json", "--threshold", "0x3")
  end

  def test_requires_unknown_scores_to_fit_the_threshold_at_zero_coverage
    write("lib/sample.rb", "def pick(x) = x ? 1 : 0\n")

    assert_equal 1, run_cli("--no-coverage", "--threshold", "5.99999999999999999999")
    assert_includes @err.string, "Cannot verify CRAP threshold"
    assert_includes @err.string, "Object#pick"
    assert_includes @err.string, "maximum 6"
    refute_includes @err.string, "threshold 6.0"
    assert_includes snapshot, ":coverage nil, :crap nil"
    assert_equal 0, run_cli("--no-coverage", "--threshold", "6")
    refute_includes @err.string, "Cannot verify"
    assert_includes snapshot, ":coverage nil, :crap nil"
  end

  def test_prioritizes_measured_violations_over_unknown_scores
    write("lib/sample.rb", "def measured(x)\n x ? 1 : 0\nend\ndef unknown(x) = x ? 1 : 0\n")
    write("results.json", JSON.generate("RSpec" => {"coverage" => {
      "lib/sample.rb" => {"lines" => [1, 0, nil, 1]}
    }}))

    assert_equal 2, run_cli("--coverage", "results.json", "--threshold", "5")
    assert_includes snapshot, ":coverage 0.0, :crap 6.0"
    assert_includes snapshot, ":coverage nil, :crap nil"
    assert_includes @err.string, "CRAP threshold exceeded"
    refute_includes @err.string, "Cannot verify"
  end

  def test_rejects_unrepresentable_method_names_without_replacing_snapshot
    write("lib/sample.rb", <<~'RUBY')
      # encoding: ASCII-8BIT
      define_method("\xFF") { true }
    RUBY
    write(".metrics/crap.edn", "previous snapshot")

    assert_equal 1, run_cli("--no-coverage")
    assert_includes @err.string, "sample.rb:2: define_method name must be representable in UTF-8"
    assert_equal "previous snapshot", snapshot
  end

  def test_escapes_control_characters_in_literal_method_names
    write("lib/sample.rb", 'define_method("line\nname") { true }')

    assert_equal 1, run_cli("--no-coverage", "--threshold", "1")
    assert_equal 5, @out.string.lines.size
    assert_includes @out.string, '"line\nname"'
    assert_equal 2, @err.string.lines.size
    assert_includes @err.string, '"Object#line\nname"'
    assert_includes snapshot, ':name "line\nname"'
  end

  def test_rejects_negative_thresholds_that_underflow_float_precision
    write(".metrics/crap.edn", "previous snapshot")

    assert_equal 1, run_cli("--threshold", "-1e-1000")
    assert_includes @err.string, "threshold must be finite and nonnegative"
    assert_equal "previous snapshot", snapshot
  end

  def test_discovers_source_and_prunes_tests_hidden_and_generated_trees
    write("app/good.rb", "def good = 1")
    %w[test/example.rb spec/example.rb features/example.rb vendor/example.rb node_modules/example.rb
      target/example.rb coverage/example.rb tmp/example.rb .hidden/example.rb app/item_test.rb
      app/item_spec.rb app/test_item.rb].each { |path| write(path, "def excluded = 1") }

    assert_equal 0, run_cli("--no-coverage")
    assert_includes snapshot, '"good"'
    refute_includes snapshot, '"excluded"'
    assert_equal 0, run_cli("--no-coverage", "test/example.rb")
    assert_includes snapshot, '"excluded"'
    refute_includes snapshot, '"good"'
  end

  def test_combines_source_roots_paths_and_fragment_filters_without_duplicates
    write("app/orders.rb", "def orders = 1")
    write("app/items.rb", "def items = 1")
    write("lib/orders.rb", "def library_orders = 1")

    assert_equal 0, run_cli("--no-coverage", "--source-root", "app", "--source-root", "lib", "orders")
    assert_includes snapshot, '"orders"'
    assert_includes snapshot, '"library_orders"'
    refute_includes snapshot, '"items"'
    assert_equal 0, run_cli("--no-coverage", "app", "app/orders.rb", "orders")
    assert_equal 1, snapshot.scan(':name "orders"').size
    refute_includes snapshot, '"library_orders"'
  end

  def test_errors_preserve_previous_snapshot
    original = "previous snapshot\n"
    write(".metrics/crap.edn", original)
    write("lib/sample.rb", "def good = 1")

    assert_equal 1, run_cli
    assert_includes @err.string, "--no-coverage"
    assert_equal original, snapshot
    write("lib/sample.rb", "def broken(")

    assert_equal 1, run_cli("--no-coverage")
    assert_includes @err.string, "sample.rb:"
    assert_equal original, snapshot
  end

  def test_help_version_invalid_options_and_empty_selection
    assert_equal 0, run_cli("--help")
    assert_includes @out.string, "--coverage-command"
    refute_path_exists File.join(@root, ".metrics")
    assert_equal 0, run_cli("--version")
    assert_includes @out.string, Crap4Ruby::VERSION
    [["--unknown"], ["--threshold", "-1"], ["--threshold", "NaN"],
      ["--no-coverage", "--coverage-command", "true"], ["--source-root", "missing"]].each do |arguments|
      assert_equal 1, run_cli(*arguments), arguments.inspect
    end
    assert_equal 0, run_cli
    assert_equal "{:entries []}\n", snapshot
  end

  def test_coverage_command_must_succeed_and_refresh_its_report
    write("lib/sample.rb", "def work\n 1\nend\n")
    write("collect.rb", <<~RUBY)
      require "json"
      puts "test output"
      File.write("result.json", JSON.generate("Test" => {"coverage" => {"lib/sample.rb" => [1, 1, nil]}}))
    RUBY
    command = "#{Shellwords.escape(RbConfig.ruby)} collect.rb"

    assert_equal 0, run_cli("--coverage", "result.json", "--coverage-command", command)
    assert_includes @err.string, "test output"
    refute_includes @out.string, "test output"
    assert_includes snapshot, ":coverage 100.0, :crap 1.0"
    original = snapshot

    assert_equal 1, run_cli("--coverage", "result.json", "--coverage-command", "true")
    assert_match(/refresh/, @err.string)
    assert_equal original, snapshot
    assert_equal 1, run_cli("--coverage", "result.json", "--coverage-command", "exit 7")
    assert_match(/7/, @err.string)
    assert_equal original, snapshot
  end

  def test_changed_files_include_staged_unstaged_untracked_and_renamed_paths
    git("init", "-q")
    write("lib/unchanged.rb", "def unchanged = 1")
    write("lib/edited.rb", "def before_edit = 1")
    write("lib/old name.rb", "def renamed = 1")
    write("lib/deleted.rb", "def deleted = 1")
    git("add", "lib")
    git("-c", "user.name=Test", "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture")
    write("lib/edited.rb", "def edited = 1")
    git("mv", "lib/old name.rb", "lib/new name.rb")
    git("rm", "-q", "lib/deleted.rb")
    write("lib/untracked ü.rb", "def untracked = 1")
    write("spec/ignored_spec.rb", "def ignored = 1")

    assert_equal 0, run_cli("--changed", "--no-coverage")
    %w[edited renamed untracked].each { |name| assert_includes snapshot, ":name #{name.to_json}" }
    %w[unchanged deleted ignored].each { |name| refute_includes snapshot, ":name #{name.to_json}" }
    assert_equal 0, run_cli("--root", File.join(@root, "lib"), "--changed", "--no-coverage", "new name.rb")
    assert_includes File.read(File.join(@root, "lib/.metrics/crap.edn")), ':name "renamed"'
  end

  def test_changed_outside_a_repository_fails_without_replacing_snapshot
    write("sample.rb", "def good = 1")
    write(".metrics/crap.edn", "keep")

    assert_equal 1, run_cli("--changed", "--no-coverage")
    assert_includes @err.string, "git:"
    assert_equal "keep", snapshot
  end

  def git(*arguments)
    output, error, status = Open3.capture3("git", "-C", @root, *arguments)
    raise "git fixture failed: #{output}#{error}" unless status.success?
  end
end
