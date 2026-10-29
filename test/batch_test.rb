# frozen_string_literal: true

require_relative "test_helper"

class BatchTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("crap4ruby-batch")
    @first = File.join(@root, "first.rb")
    @second = File.join(@root, "second.rb")
    File.write(@first, "def one(x)\n x ? 1 : 0\nend\n")
    File.write(@second, "def two(x)\n x ||= 1\n x\nend\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def test_serial_batch_preserves_order_and_coverage
    coverage = Crap4Ruby::Coverage.new({"Test" => {"coverage" => {
      @first => [1, 1, nil], @second => [1, 1, 0, nil]
    }}}, root: @root)

    entries = Crap4Ruby::Batch.call([@second, @first], coverage, jobs: 1)

    assert_equal [
      Crap4Ruby::Entry.new("two", "Object", 2, 50.0, Rational(5, 2), @second),
      Crap4Ruby::Entry.new("one", "Object", 2, 100.0, Rational(2), @first)
    ], entries
  end

  def test_complexity_only_batch_leaves_scores_unknown
    assert_equal [Crap4Ruby::Entry.new("one", "Object", 2, nil, nil, @first)],
      Crap4Ruby::Batch.call([@first], nil)
  end

  def test_empty_batch_returns_no_entries
    assert_empty Crap4Ruby::Batch.call([], nil)
  end

  def test_rejects_nonpositive_worker_counts
    [0, -1].each do |jobs|
      assert_raises(ArgumentError) { Crap4Ruby::Batch.call([@first], nil, jobs: jobs) }
    end
  end

  def test_batch_preserves_parse_and_filesystem_errors
    File.write(@second, "def broken(")

    error = assert_raises(Crap4Ruby::Error) { Crap4Ruby::Batch.call([@second], nil) }
    assert_includes error.message, "#{@second}:"
    assert_raises(Errno::ENOENT) { Crap4Ruby::Batch.call([File.join(@root, "missing.rb")], nil) }
  end
end
