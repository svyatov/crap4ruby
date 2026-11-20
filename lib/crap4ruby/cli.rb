# frozen_string_literal: true

require "optparse"

module Crap4Ruby
  # Coordinates file discovery, coverage, scoring, and CLI output.
  class CLI
    # Options used exclusively when comparing two JSON reports.
    COMPARISON_FLAGS = %i[base_report head_report enforce limit min_increase].freeze
    COMPARISON_OPTIONS = (COMPARISON_FLAGS + %i[source_roots compare]).freeze

    # Sets output destinations without running an analysis.
    #
    # @param stdout [#puts, #write] destination for reports, help, and version output
    # @param stderr [#puts, #write] destination for diagnostics and coverage command output
    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    # Runs the requested analysis and replaces the snapshot unless --no-save is set.
    # Help and version requests produce output without writing a snapshot.
    # Expected usage, input, filesystem, and command errors are printed to stderr.
    #
    # @param arguments [Array<String>] command-line tokens; option parsing mutates this array
    # @return [Integer] 0 on success, 1 on error or an uncertain threshold, 2 on a measured violation
    # @example Analyze complexity without coverage
    #   CLI.new.run(["--no-coverage", "--source-root", "lib"])
    def run(arguments)
      options, parser, paths = parse_options(arguments)
      return @stdout.puts(parser) || 0 if options[:help]
      return @stdout.puts(VERSION) || 0 if options[:version]

      options[:compare] ? compare(options, paths) : analyze(options, paths)
    rescue Error, OptionParser::ParseError, SystemCallError => error
      @stderr.puts("crap4ruby: #{error.message}")
      1
    end

    private

    def analyze(options, paths)
      validate_scan_options(options, paths)
      root = File.realpath(options.fetch(:root, Dir.pwd))
      raise Error, "#{root}: project root must be a directory" unless File.directory?(root)

      scope = BaselineReport.scope(root, options[:source_roots]) if options[:json_report]
      source_roots = scope&.map { |path| File.join(root, path) } || options[:source_roots]
      files = Discovery.call(root: root, source_roots: source_roots, paths: paths,
        changed: options[:changed] == true)
      BaselineReport.validate_files!(root, files) if scope
      coverage, coverage_source = load_coverage(options, root, files.empty?)
      entries = Report.sorted(Batch.call(files, coverage, jobs: options[:jobs]))
      output = analysis_output(entries, root, files.size, coverage_source, scope, options)
      @stderr.puts("Wrote #{Report.write(entries, root: root)}") unless options[:no_save]
      @stdout.write(output)
      threshold_status(entries, options[:threshold])
    end

    def analysis_output(entries, root, files, coverage_source, scope, options)
      if scope
        path = options.fetch(:coverage, "coverage/.resultset.json") if coverage_source.is_a?(String)
        return BaselineReport.dump(entries, root: root, source_roots: scope, coverage_path: path,
          revision: options.fetch(:revision))
      end

      Report.terminal(entries, root: root, files: files, coverage_source: coverage_source,
        threshold: options.fetch(:threshold, 30), limit: options[:threshold_label], verbose: options[:verbose] == true)
    end

    # Removes parsed options from arguments and returns the remaining path selectors.
    #
    # @param arguments [Array<String>] mutable command-line tokens
    # @return [Array(Hash, OptionParser, Array<String>)] options, parser, and remaining selectors
    # @raise [OptionParser::ParseError] if an option or threshold is invalid
    def parse_options(arguments)
      # @type var options: options
      options = {source_roots: []}
      parser = OptionParser.new do |cli|
        cli.banner = "Usage: crap4ruby [options] [file-or-directory-or-filter ...]"
        cli.separator "Default output: CRAP > 30 and unknown scores; --threshold sets the display limit."
        cli.on("--root PATH", "Project root (default: current directory)") do |path|
          # @type var path: String
          options[:root] = path
        end
        cli.on("--source-root PATH", "Analyze this directory; repeat for multiple roots") do |path|
          # @type var path: String
          options[:source_roots] << path
        end
        cli.on("--changed", "Analyze Git additions and edits, including untracked files") { options[:changed] = true }
        cli.on("--coverage PATH", "SimpleCov resultset (default: coverage/.resultset.json)") do |path|
          # @type var path: String
          options[:coverage] = path
        end
        cli.on("--no-coverage", "Complexity only; coverage and CRAP are N/A") { options[:no_coverage] = true }
        cli.on("--no-save", "Print results without writing .metrics/crap.edn") { options[:no_save] = true }
        cli.on("--verbose", "Show all analyzed methods") { options[:verbose] = true }
        cli.on("--jobs N", Integer, "Worker processes (default: automatic; 1 disables workers)") do |jobs|
          # @type var jobs: Integer
          raise OptionParser::InvalidArgument, "jobs must be positive" if jobs < 1

          options[:jobs] = jobs
        end
        cli.on("--use-existing-coverage", "Read reports without running tests (the default)") do
          options[:existing] = true
        end
        cli.on("--coverage-command COMMAND", "Run a shell command that refreshes the resultset") do |command|
          # @type var command: String
          options[:command] = command
        end
        cli.on("--threshold NUMBER", "Exit 2 above limit; exit 1 if unknown scores could exceed it") do |value|
          # @type var value: String
          options[:threshold] = nonnegative_number(value, "--threshold")
          options[:threshold_label] = value.strip
        end
        add_comparison_options(cli, options)
        cli.on("-h", "--help", "Show help") { options[:help] = true }
        cli.on("-v", "--version", "Show version") { options[:version] = true }
      end
      [options, parser, parser.parse(arguments)]
    end

    def add_comparison_options(cli, options)
      cli.on("--json-report", "Export a complete versioned JSON report") { options[:json_report] = true }
      cli.on("--revision SHA", "Full commit ID for --json-report") do |value|
        # @type var value: String
        options[:revision] = value
      end
      cli.on("--compare", "Compare --base-report and --head-report as Markdown") { options[:compare] = true }
      cli.on("--base-report PATH", "JSON report for the base revision") do |value|
        # @type var value: String
        options[:base_report] = value
      end
      cli.on("--head-report PATH", "JSON report for the head revision") do |value|
        # @type var value: String
        options[:head_report] = value
      end
      cli.on("--fail-on-regression", "Enforce the comparison verdict") { options[:enforce] = true }
      cli.on("--limit NUMBER", "CRAP limit for --compare (default: 30)") do |value|
        # @type var value: String
        options[:limit] = nonnegative_number(value, "--limit")
      end
      cli.on("--min-increase NUMBER", "Minimum material increase for --compare (default: 1)") do |value|
        # @type var value: String
        options[:min_increase] = nonnegative_number(value, "--min-increase")
      end
    end

    def nonnegative_number(value, flag)
      number = Float(value)
      raise ArgumentError unless number.finite?

      exact = Rational(value, exception: false) || number.to_r
      raise ArgumentError if exact.negative?

      exact
    rescue ArgumentError
      raise OptionParser::InvalidArgument, "#{flag} must be finite and nonnegative"
    end

    def compare(options, paths)
      if !paths.empty? || !options[:source_roots].empty? || !(options.keys - COMPARISON_OPTIONS).empty?
        raise Error, "--compare cannot be combined with scan options"
      end

      base_path = options[:base_report]
      head_path = options[:head_report]
      raise Error, "--compare requires --base-report and --head-report" unless base_path && head_path

      base = BaselineReport.load(base_path)
      head = BaselineReport.load(head_path)
      BaselineReport.check_compatible!(base, head)
      result = BaselineComparison.call(base, head, limit: options.fetch(:limit, Rational(30)),
        min_increase: options.fetch(:min_increase, Rational(1)))
      enforced = options[:enforce] == true
      @stdout.write(BaselineComparison.markdown(result, enforced: enforced))
      enforced ? result.status : 0
    end

    def validate_scan_options(options, paths)
      raise Error, "comparison options require --compare" if COMPARISON_FLAGS.any? { |flag| options.key?(flag) }

      validate_export(options, paths) if options[:json_report] || options[:revision]
      validate_options(options)
    end

    def validate_export(options, paths)
      raise Error, "--revision requires --json-report" unless options[:json_report]
      raise Error, "--json-report requires --revision SHA" unless options[:revision]
      return unless options[:changed] || options[:no_coverage] || !paths.empty?

      raise Error, "--json-report requires coverage and a complete source scope"
    end

    # Rejects a coverage command when coverage is disabled or explicitly read-only.
    #
    # @param options [Hash] parsed CLI options
    # @return [void]
    # @raise [Error] if coverage options conflict
    def validate_options(options)
      return unless options[:command] && (options[:no_coverage] || options[:existing])

      raise Error, "--coverage-command cannot be combined with --no-coverage or --use-existing-coverage"
    end

    # Checks measured scores and bounds unknown scores at zero coverage.
    #
    # @param entries [Array<Entry>] scored methods
    # @param threshold [Rational, nil] maximum allowed score, or nil to disable the check
    # @return [Integer] 2 for a measured violation, 1 if uncertain, otherwise 0
    def threshold_status(entries, threshold)
      return 0 unless threshold

      if entries.any? { |entry| entry.crap && entry.crap > threshold }
        @stderr.puts("CRAP threshold exceeded")
        return 2
      end

      uncertain = entries.select { |entry| !entry.crap && entry.complexity * (entry.complexity + 1) > threshold }
      uncertain.each do |entry|
        @stderr.puts("Cannot verify CRAP threshold: #{Report.label("#{entry.namespace}##{entry.name}")} " \
                     "has unknown coverage (maximum #{entry.complexity * (entry.complexity + 1)})")
      end
      uncertain.empty? ? 0 : 1
    end

    def load_coverage(options, root, empty)
      return [nil, false] if options[:no_coverage]
      return [nil, nil] if empty

      report = File.expand_path(options.fetch(:coverage, "coverage/.resultset.json"), root)
      run_coverage(options[:command], root, report) if options[:command]
      [Coverage.load(report, root: root), report]
    end

    # Runs a shell command at root and forwards its combined output to stderr.
    # Requires success and a changed report stamp before coverage can be consumed.
    #
    # @param command [String] command passed to `sh -c` with the caller's environment
    # @param root [String] command working directory
    # @param report [String] expected coverage report path
    # @return [void]
    # @raise [Error] if the command is empty, fails, or leaves the report stamp unchanged
    # @raise [SystemCallError] if the command cannot start or report metadata cannot be read
    def run_coverage(command, root, report)
      raise Error, "--coverage-command must not be empty" if command.strip.empty?

      before = report_stamp(report)
      status = Open3.popen2e("sh", "-c", command, chdir: root) do |input, output, process|
        input.close
        output.each_line { |line| @stderr.write(line) }
        process.value
      end
      unless status.success?
        raise Error,
          "coverage command failed (exit #{status.exitstatus || "signal #{status.termsig}"})"
      end
      raise Error, "coverage command did not refresh #{report}" if report_stamp(report) == before
    end

    # Captures metadata used to detect a newly generated or refreshed report.
    #
    # @param path [String] coverage report path
    # @return [Array(Integer, Time, Time, Integer), nil] inode, modification time,
    #   change time, and size; nil if the path does not exist
    def report_stamp(path)
      stat = File.stat(path)
      [stat.ino, stat.mtime, stat.ctime, stat.size]
    rescue Errno::ENOENT
      nil
    end
  end
end
