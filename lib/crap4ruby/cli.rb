# frozen_string_literal: true

require "optparse"

module Crap4Ruby
  # Coordinates file discovery, coverage, scoring, and CLI output.
  class CLI
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

      validate_options(options)
      root = File.realpath(options[:root])
      raise Error, "#{root}: project root must be a directory" unless File.directory?(root)

      files = Discovery.call(root: root, source_roots: options[:source_roots], paths: paths, changed: options[:changed])
      coverage = load_coverage(options, root) unless options[:no_coverage] || files.empty?
      entries = Report.sorted(analyze(files, coverage))
      unless options[:no_save]
        path = Report.write(entries, root: root)
        @stderr.puts("Wrote #{path}")
      end
      @stdout.write(Report.table(entries))
      threshold_status(entries, options[:threshold])
    rescue Error, OptionParser::ParseError, SystemCallError => error
      @stderr.puts("crap4ruby: #{error.message}")
      1
    end

    private

    def analyze(files, coverage)
      Batch.call(files, coverage)
    end

    # Removes parsed options from arguments and returns the remaining path selectors.
    #
    # @param arguments [Array<String>] mutable command-line tokens
    # @return [Array(Hash, OptionParser, Array<String>)] options, parser, and remaining selectors
    # @raise [OptionParser::ParseError] if an option or threshold is invalid
    def parse_options(arguments)
      # @type var options: options
      options = {root: Dir.pwd, source_roots: [], changed: false, coverage: "coverage/.resultset.json"}
      parser = OptionParser.new do |cli|
        cli.banner = "Usage: crap4ruby [options] [file-or-directory-or-filter ...]"
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
        cli.on("--use-existing-coverage", "Read reports without running tests (the default)") do
          options[:existing] = true
        end
        cli.on("--coverage-command COMMAND", "Run a shell command that refreshes the resultset") do |command|
          # @type var command: String
          options[:command] = command
        end
        cli.on("--threshold NUMBER", "Exit 2 above limit; exit 1 if unknown scores could exceed it") do |value|
          # @type var value: String
          number = Float(value)
          raise ArgumentError unless number.finite?

          threshold = Rational(value, exception: false) || number.to_r
          raise ArgumentError if threshold.negative?

          options[:threshold] = threshold
        rescue ArgumentError
          raise OptionParser::InvalidArgument, "threshold must be finite and nonnegative"
        end
        cli.on("-h", "--help", "Show help") { options[:help] = true }
        cli.on("-v", "--version", "Show version") { options[:version] = true }
      end
      [options, parser, parser.parse(arguments)]
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

    def load_coverage(options, root)
      report = File.expand_path(options[:coverage], root)
      run_coverage(options[:command], root, report) if options[:command]
      Coverage.load(report, root: root)
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
