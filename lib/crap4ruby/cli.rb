# frozen_string_literal: true

require "optparse"

module Crap4Ruby
  class CLI
    def initialize(stdout: $stdout, stderr: $stderr)
      @stdout = stdout
      @stderr = stderr
    end

    def run(arguments)
      options, parser, paths = parse_options(arguments)
      return @stdout.puts(parser) || 0 if options[:help]
      return @stdout.puts(VERSION) || 0 if options[:version]

      validate_options(options)
      root = File.realpath(options[:root])
      raise Error, "#{root}: project root must be a directory" unless File.directory?(root)

      files = Discovery.call(root: root, source_roots: options[:source_roots], paths: paths, changed: options[:changed])
      coverage = load_coverage(options, root) unless options[:no_coverage] || files.empty?
      entries = files.flat_map do |path|
        Analyzer.new.call(File.binread(path), path: path).map { |method| Score.call(method, coverage) }
      end
      entries = Report.sorted(entries)
      path = Report.write(entries, root: root)
      @stdout.write(Report.table(entries))
      @stderr.puts("Wrote #{path}")
      threshold_status(entries, options[:threshold])
    rescue Error, OptionParser::ParseError, SystemCallError => error
      @stderr.puts("crap4ruby: #{error.message}")
      1
    end

    private

    def parse_options(arguments)
      options = {root: Dir.pwd, source_roots: [], changed: false, coverage: "coverage/.resultset.json"}
      parser = OptionParser.new do |cli|
        cli.banner = "Usage: crap4ruby [options] [file-or-directory-or-filter ...]"
        cli.on("--root PATH", "Project root (default: current directory)") { |path| options[:root] = path }
        cli.on("--source-root PATH", "Analyze this directory; repeat for multiple roots") { |path| options[:source_roots] << path }
        cli.on("--changed", "Analyze Git additions and edits, including untracked files") { options[:changed] = true }
        cli.on("--coverage PATH", "SimpleCov resultset (default: coverage/.resultset.json)") { |path| options[:coverage] = path }
        cli.on("--no-coverage", "Complexity only; coverage and CRAP are N/A") { options[:no_coverage] = true }
        cli.on("--use-existing-coverage", "Read reports without running tests (the default)") { options[:existing] = true }
        cli.on("--coverage-command COMMAND", "Run a shell command that refreshes the resultset") { |command| options[:command] = command }
        cli.on("--threshold NUMBER", "Exit 2 when CRAP exceeds this value") do |value|
          number = Float(value)
          raise OptionParser::InvalidArgument, "threshold must be finite and nonnegative" unless number.finite? && number >= 0

          options[:threshold] = number
        rescue ArgumentError
          raise OptionParser::InvalidArgument, "threshold must be finite and nonnegative"
        end
        cli.on("-h", "--help", "Show help") { options[:help] = true }
        cli.on("-v", "--version", "Show version") { options[:version] = true }
      end
      [options, parser, parser.parse(arguments)]
    end

    def validate_options(options)
      if options[:command] && (options[:no_coverage] || options[:existing])
        raise Error, "--coverage-command cannot be combined with --no-coverage or --use-existing-coverage"
      end
    end

    def threshold_status(entries, threshold)
      if threshold && entries.any? { |entry| entry.crap && entry.crap > threshold }
        @stderr.puts("CRAP threshold exceeded: #{threshold}")
        2
      else
        0
      end
    end

    def load_coverage(options, root)
      report = File.expand_path(options[:coverage], root)
      run_coverage(options[:command], root, report) if options[:command]
      Coverage.load(report, root: root)
    end

    def run_coverage(command, root, report)
      raise Error, "--coverage-command must not be empty" if command.strip.empty?

      before = report_stamp(report)
      status = Open3.popen2e("sh", "-c", command, chdir: root) do |input, output, process|
        input.close
        output.each_line { |line| @stderr.write(line) }
        process.value
      end
      raise Error, "coverage command failed (exit #{status.exitstatus || "signal #{status.termsig}"})" unless status.success?
      raise Error, "coverage command did not refresh #{report}" if report_stamp(report) == before
    end

    def report_stamp(path)
      stat = File.stat(path)
      [stat.ino, stat.mtime, stat.ctime, stat.size]
    rescue Errno::ENOENT
      nil
    end
  end
end
