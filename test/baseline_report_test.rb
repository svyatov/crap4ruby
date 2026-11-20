# frozen_string_literal: true

require_relative "test_helper"

class BaselineReportTest < Minitest::Test
  REVISION = "0123456789abcdef0123456789abcdef01234567"

  def record
    {
      "path" => "lib/sample.rb", "line" => 2, "namespace" => "Example", "kind" => "instance",
      "name" => "work", "complexity" => 2, "coverage" => 66.66666666666667, "crap" => "58/27", "coverage_note" => nil
    }
  end

  def document
    {
      "schema_version" => 1, "tool_version" => Crap4Ruby::VERSION, "prism_version" => Prism::VERSION,
      "revision" => REVISION, "source_roots" => ["lib"], "coverage_path" => "coverage/.resultset.json"
    }
  end

  def read_document(document, entries)
    read_text(JSON.generate(document.merge("entries" => entries)))
  end

  def read_text(text)
    Dir.mktmpdir do |root|
      path = File.join(root, "report.json")
      File.binwrite(path, text)
      Crap4Ruby::BaselineReport.load(path)
    end
  end

  def test_round_trips_exact_scores_and_preserves_literal_names_and_repeated_definitions
    path = File.join(Dir.pwd, "lib/пример.rb")
    instance = Crap4Ruby::Entry.new("self.work", "Example", 2, 66.66666666666667, Rational(58, 27), path, 3, nil, false)
    singleton = Crap4Ruby::Entry.new("self.work", "Example", 2, nil, nil, path, 1, :shared_declaration, true)
    entries = [instance, singleton, instance]
    # @type var options: {root: String, source_roots: Array[String], coverage_path: String, revision: String}
    options = {root: Dir.pwd, source_roots: ["lib"], coverage_path: "coverage/results.json", revision: REVISION}

    text = Crap4Ruby::BaselineReport.dump(entries, **options)
    report = read_text(text)

    results = report.entries.map { |entry| [entry.kind, entry.name, entry.line, entry.crap, entry.coverage_note] }

    assert_equal Crap4Ruby::BaselineReport.dump(entries.reverse, **options), text
    assert_includes text, "58/27"
    assert_equal REVISION, report.revision
    assert_equal "coverage/results.json", report.coverage_path
    assert_equal ["lib"], report.source_roots
    assert_equal [["singleton", "work", 1, nil, "shared_declaration"],
      ["instance", "self.work", 3, Rational(58, 27), nil],
      ["instance", "self.work", 3, Rational(58, 27), nil]], results
    assert_equal ["lib/пример.rb"], report.entries.map(&:path).uniq
  end

  def test_records_zero_coverage_for_a_file_absent_from_the_resultset
    report = read_document(document, [record.merge("coverage" => 0, "crap" => "6/1", "coverage_note" => "absent_file")])
    entry = report.entries.fetch(0)

    assert_equal 0, entry.coverage
    assert_equal Rational(6), entry.crap
    assert_equal "absent_file", entry.coverage_note
  end

  def test_rejects_inconsistent_measurement_records
    [
      [nil, "58/27", nil],
      [50, nil, "no_measurable_lines"],
      [50, "58/27", "shared_declaration"],
      [nil, nil, "absent_file"],
      [nil, nil, nil],
      [50, "58/27", "absent_file"],
      [0, "58/27", "absent_file"],
      [nil, nil, "unrecognized"]
    ].each do |coverage, crap, reason|
      entry = record.merge("coverage" => coverage, "crap" => crap, "coverage_note" => reason)
      error = assert_raises(Crap4Ruby::Error) { read_document(document, [entry]) }
      assert_match(/coverage_note/, error.message)
    end
  end

  def test_rejects_malformed_entry_fields
    {
      "path" => ["/sample.rb", "../lib/sample.rb", "./lib/sample.rb", "lib//sample.rb", "lib/x/../sample.rb",
        "lib/a\u0000.rb", "elsewhere/sample.rb"],
      "line" => [0, 2.0, "2"],
      "namespace" => ["", nil],
      "kind" => ["class", nil],
      "name" => [2],
      "complexity" => [0, -1, 2.0],
      "coverage" => [-0.01, 100.01, "50"],
      "crap" => ["2.5", "2/0", "6/-1", "1/1", "7/1", 2.5]
    }.each do |field, invalid_values|
      invalid_values.each do |value|
        error = assert_raises(Crap4Ruby::Error) { read_document(document, [record.merge(field => value)]) }
        assert_includes error.message, field
      end
    end
  end

  def test_rejects_malformed_report_fields
    empty = [] #: Array[Crap4Ruby::json]
    {
      "schema_version" => [2, 1.0],
      "tool_version" => ["", 2],
      "prism_version" => ["", nil],
      "revision" => ["deadbeef", "g" * 40],
      "source_roots" => [empty, ["lib", "."], %w[lib lib], ["/lib"], ["../lib"], [nil]],
      "coverage_path" => ["", nil, "coverage/a\u0000.json"]
    }.each do |field, invalid_values|
      invalid_values.each do |value|
        error = assert_raises(Crap4Ruby::Error) { read_document(document.merge(field => value), [record]) }
        assert_includes error.message, field
      end
    end
  end

  def test_rejects_invalid_json_and_wrong_object_shapes
    ["{!", "null", "{\"schema_version\":1,\"schema_version\":1}", "{\"\xFF\":1}"].each do |text|
      error = assert_raises(Crap4Ruby::Error) { read_text(text) }
      assert_match(/report.json.*invalid baseline report/, error.message)
    end

    assert_raises(Crap4Ruby::Error) { read_document(document.merge("extra" => 1), []) }
    assert_raises(Crap4Ruby::Error) { read_document(document, [record.reject { |key| key == "name" }]) }
    assert_raises(Crap4Ruby::Error) { read_document(document, [nil]) }
  end

  def test_reports_an_unreadable_input_with_its_path
    Dir.mktmpdir do |root|
      path = File.join(root, "missing.json")
      error = assert_raises(Crap4Ruby::Error) { Crap4Ruby::BaselineReport.load(path) }

      assert_includes error.message, path
    end
  end

  def test_allows_an_empty_scan_and_different_coverage_paths_at_the_same_revision
    base = read_document(document.merge("coverage_path" => nil), [])
    head = read_document(document.merge("coverage_path" => "coverage/other.json"), [record])

    assert_empty base.entries
    assert_nil base.coverage_path
    assert_equal base.revision, head.revision
    Crap4Ruby::BaselineReport.check_compatible!(base, head)
  end

  def test_rejects_incompatible_tool_versions_and_scopes
    base = read_document(document, [record])

    {"tool_version" => "0.0.1", "prism_version" => "1.0.0", "source_roots" => ["."]}.each do |field, value|
      head = read_document(document.merge(field => value), [record])
      error = assert_raises(Crap4Ruby::Error) { Crap4Ruby::BaselineReport.check_compatible!(base, head) }
      assert_includes error.message, field
    end
  end

  def test_normalizes_relative_source_roots
    Dir.mktmpdir do |root|
      FileUtils.mkdir_p([File.join(root, "lib"), File.join(root, "app")])
      File.symlink(File.join(root, "lib"), File.join(root, "alias"))

      assert_equal ["."], Crap4Ruby::BaselineReport.scope(root, [])
      assert_equal %w[app lib], Crap4Ruby::BaselineReport.scope(root, %w[./lib/ app lib alias])
    end
  end

  def test_rejects_missing_absolute_and_escaping_source_roots
    Dir.mktmpdir do |parent|
      root = File.join(parent, "project")
      FileUtils.mkdir_p(root)
      File.symlink(parent, File.join(root, "outside"))

      ["missing", root, "..", "outside", ""].each do |path|
        error = assert_raises(Crap4Ruby::Error) { Crap4Ruby::BaselineReport.scope(root, [path]) }
        assert_includes error.message, "source root"
      end
    end
  end

  def test_validates_selected_paths_even_when_files_have_no_methods
    root = Dir.pwd
    Crap4Ruby::BaselineReport.validate_files!(root, [File.join(root, "lib/пример.rb")])
    error = assert_raises(Crap4Ruby::Error) do
      Crap4Ruby::BaselineReport.validate_files!(root, [File.join(root, "lib/bad\xFF.rb")])
    end

    assert_includes error.message, "UTF-8"
    assert_includes error.message, 'bad\xFF.rb'
  end

  def test_export_rejects_paths_that_cannot_be_represented_in_utf8
    entry = Crap4Ruby::Entry.new("work", "Example", 2, nil, nil, "lib/bad\xFF.rb", 2, :no_measurable_lines, false)
    error = assert_raises(Crap4Ruby::Error) do
      Crap4Ruby::BaselineReport.dump([entry], root: Dir.pwd, source_roots: ["lib"], coverage_path: "cov.json",
        revision: REVISION)
    end

    assert_includes error.message, "UTF-8"
    assert_includes error.message, 'bad\xFF.rb'
  end
end
