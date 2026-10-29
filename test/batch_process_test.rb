# frozen_string_literal: true

require_relative "test_helper"
require "open3"
require "timeout"

class BatchProcessTest < Minitest::Test
  def setup
    @root = Dir.mktmpdir("crap4ruby-workers")
    File.write(File.join(@root, "first.rb"), "def first = 1\n")
    File.write(File.join(@root, "second.rb"), "def second = 2\n")
  end

  def teardown
    FileUtils.remove_entry(@root)
  end

  def run_program(program)
    prefix = <<~'RUBY'
      require "simplecov"
      SimpleCov.start do
        root Dir.pwd
        command_name "batch process #{Process.pid}"
        cover "lib/**/*.rb"
      end
      SimpleCov.formatters = []
      require "crap4ruby"
      root = ARGV.fetch(0)
      files = %w[second.rb first.rb].map { |name| File.join(root, name) }
    RUBY
    Open3.popen3(RbConfig.ruby, "-Ilib", "-rjson", "-e", prefix + program, @root,
      pgroup: true) do |input, output, error, process|
      input.close
      begin
        Timeout.timeout(10) { yield output.read, error.read, process.value }
      rescue Timeout::Error
        Process.kill("KILL", -process.pid)

        flunk "batch subprocess exceeded 10 seconds"
      end
    end
  end

  def pid_tracer
    <<~RUBY
      Crap4Ruby::Analyzer.prepend(Module.new do
        def call(source, path:)
          super.map { |method| method.with(namespace: Process.pid.to_s) }
        end
      end)
    RUBY
  end

  def test_explicit_workers_preserve_order_and_run_in_children
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(pid_tracer + <<~RUBY) do |output, error, status|
      entries = Crap4Ruby::Batch.call(files, nil, jobs: 8)
      puts JSON.generate(names: entries.map(&:name), pids: entries.map(&:namespace), parent: Process.pid.to_s)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { names: Array[String], pids: Array[String], parent: String }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal %w[second first], result.fetch(:names)
      assert_equal 2, result.fetch(:pids).uniq.size
      refute_includes result.fetch(:pids), result.fetch(:parent)
    end
  end

  def test_automatic_workers_are_bounded_and_small_batches_stay_serial
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(pid_tracer + <<~RUBY) do |output, error, status|
      require "etc"
      small = Crap4Ruby::Batch.call(files, nil)
      large = Crap4Ruby::Batch.call(files * 64, nil)
      puts JSON.generate(small: small.map(&:namespace).uniq, large: large.map(&:namespace).uniq,
        parent: Process.pid.to_s, expected: [4, Etc.nprocessors].min)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { small: Array[String], large: Array[String], parent: String, expected: Integer }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal [result.fetch(:parent)], result.fetch(:small)
      assert_equal result.fetch(:expected), result.fetch(:large).size
    end
  end

  def test_multithreaded_hosts_stay_serial
    run_program(pid_tracer + <<~RUBY) do |output, error, status|
      gate = Queue.new
      thread = Thread.new { gate.pop }
      entries = Crap4Ruby::Batch.call(files, nil, jobs: 2)
      gate << true
      thread.join
      puts JSON.generate(pids: entries.map(&:namespace).uniq, parent: Process.pid.to_s)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { pids: Array[String], parent: String }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal [result.fetch(:parent)], result.fetch(:pids)
    end
  end

  def test_hosts_without_fork_stay_serial
    run_program(pid_tracer + <<~RUBY) do |output, error, status|
      Process.singleton_class.undef_method(:fork) if Process.respond_to?(:fork)
      entries = Crap4Ruby::Batch.call(files, nil, jobs: 2)
      puts JSON.generate(pids: entries.map(&:namespace).uniq, parent: Process.pid.to_s)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { pids: Array[String], parent: String }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal [result.fetch(:parent)], result.fetch(:pids)
    end
  end

  def test_unimplemented_fork_stays_serial
    run_program(pid_tracer + <<~RUBY) do |output, error, status|
      Process.define_singleton_method(:fork) { |&block| raise NotImplementedError }
      entries = Crap4Ruby::Batch.call(files, nil, jobs: 2)
      puts JSON.generate(pids: entries.map(&:namespace).uniq, parent: Process.pid.to_s)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { pids: Array[String], parent: String }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal [result.fetch(:parent)], result.fetch(:pids)
    end
  end

  def test_analysis_errors_keep_serial_order_and_reap_children
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      files.each { |path| File.write(path, "def broken(") }
      Crap4Ruby::Analyzer.prepend(Module.new do
        def call(source, path:)
          sleep(0.05) if path.end_with?("second.rb")
          super
        end
      end)
      begin
        Crap4Ruby::Batch.call(files, nil, jobs: 2)
      rescue Crap4Ruby::Error => error
        puts error.message
      end
      begin
        Process.wait(-1, Process::WNOHANG)
        abort "child was not reaped"
      rescue Errno::ECHILD
      end
    RUBY
      assert status.success?, "#{output}\n#{error}"
      assert_includes output, "second.rb:"
      refute_includes output, "first.rb:"
    end
  end

  def test_parallel_coverage_matches_exact_serial_scores
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~'RUBY') do |output, error, status|
      files.each { |path| File.write(path, "def pick(x)\n x ||= 1\n x\nend\n") }
      coverage = Crap4Ruby::Coverage.new({"Test" => {"coverage" => {
        files[0] => [1, 1, 0, nil], files[1] => [1, 1, 1, nil]
      }}}, root: root)
      serial = Crap4Ruby::Batch.call(files, coverage, jobs: 1)
      parallel = Crap4Ruby::Batch.call(files, coverage, jobs: 2)
      puts JSON.generate(equal: serial == parallel, scores: parallel.map { |entry| entry.crap.to_s })
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { equal: bool, scores: Array[String] }
      result = JSON.parse(output, symbolize_names: true)

      assert result.fetch(:equal)
      assert_equal ["5/2", "2/1"], result.fetch(:scores)
    end
  end

  def test_parallel_filesystem_errors_keep_their_class
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      File.unlink(files[1])
      begin
        Crap4Ruby::Batch.call(files, nil, jobs: 2)
        abort "missing file was accepted"
      rescue Errno::ENOENT => error
        puts error.message
      end
    RUBY
      assert status.success?, "#{output}\n#{error}"
      assert_includes output, "first.rb"
      assert_empty error
    end
  end

  def test_abnormal_worker_exit_returns_a_controlled_error
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      parent = Process.pid
      Crap4Ruby::Analyzer.prepend(Module.new do
        define_method(:call) do |source, path:|
          Process.exit!(17) unless Process.pid == parent
          super(source, path: path)
        end
      end)
      begin
        Crap4Ruby::Batch.call(files, nil, jobs: 2)
        abort "worker did not fail"
      rescue Crap4Ruby::Error => error
        puts error.message
      end
    RUBY
      assert status.success?, "#{output}\n#{error}"
      assert_match(/worker/, output)
    end
  end

  def test_large_payloads_match_serial_entries_without_blocking
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~'RUBY') do |output, error, status|
      source = (1..2000).map { |index| "def method_#{index}_#{'a' * 200} = 1\n" }.join
      files.each { |path| File.write(path, source) }
      serial = Crap4Ruby::Batch.call(files, nil, jobs: 1)
      parallel = Crap4Ruby::Batch.call(files, nil, jobs: 2)
      puts JSON.generate(equal: serial == parallel, entries: parallel.size)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { equal: bool, entries: Integer }
      result = JSON.parse(output, symbolize_names: true)

      assert result.fetch(:equal)
      assert_equal 4000, result.fetch(:entries)
    end
  end

  def test_invalid_and_missing_payloads_return_controlled_errors
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      Marshal.singleton_class.prepend(Module.new do
        def dump(value, destination = nil)
          return destination.write("corrupt") if $payload_mode == :corrupt
          return if $payload_mode == :missing

          super(nil, destination)
        end
      end)
      messages = [:corrupt, :missing, :wrong_type].map do |mode|
        $payload_mode = mode
        begin
          Crap4Ruby::Batch.call(files, nil, jobs: 2)
          abort "invalid payload was accepted"
        rescue Crap4Ruby::Error => error
          error.message
        end
      end
      puts JSON.generate(messages)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var messages: Array[String]
      messages = JSON.parse(output)

      assert_equal 3, messages.size
      assert_match(/worker/, output)
    end
  end

  def test_partial_start_failure_reaps_children_before_serial_fallback
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(pid_tracer + <<~RUBY) do |output, error, status|
      started = []
      calls = 0
      Process.singleton_class.prepend(Module.new do
        define_method(:fork) do |&block|
          calls += 1
          raise Errno::EAGAIN if calls == 2

          super(&block).tap { |pid| started << pid }
        end
      end)
      entries = Crap4Ruby::Batch.call(files, nil, jobs: 2)
      started.each do |pid|
        begin
          Process.wait(pid, Process::WNOHANG)
          abort "child was not reaped"
        rescue Errno::ECHILD
        end
      end
      puts JSON.generate(names: entries.map(&:name), pids: entries.map(&:namespace).uniq, parent: Process.pid.to_s)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { names: Array[String], pids: Array[String], parent: String }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal %w[second first], result.fetch(:names)
      assert_equal [result.fetch(:parent)], result.fetch(:pids)
    end
  end

  def test_interrupt_cancels_and_reaps_running_workers
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      parent = Process.pid
      interrupter = Process.fork do
        sleep(0.2)
        Process.kill("INT", parent)
        Process.exit!(0)
      end
      Crap4Ruby::Analyzer.prepend(Module.new do
        def call(source, path:)
          sleep(30)
          super
        end
      end)
      begin
        Crap4Ruby::Batch.call(files, nil, jobs: 2)
        abort "analysis was not interrupted"
      rescue Interrupt
        puts "cancelled"
      end
      Process.wait(interrupter)
      begin
        Process.wait(-1, Process::WNOHANG)
        abort "child was not reaped"
      rescue Errno::ECHILD
      end
    RUBY
      assert status.success?, "#{output}\n#{error}"
      assert_equal "cancelled\n", output
    end
  end

  def test_child_close_failure_does_not_run_inherited_exit_hooks
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      parent = Process.pid
      marker = File.join(root, "exit-hook")
      at_exit { File.write(marker, "ran") unless Process.pid == parent }
      IO.prepend(Module.new do
        define_method(:close) do
          raise IOError, "close failed" unless Process.pid == parent

          super()
        end
      end)
      begin
        Crap4Ruby::Batch.call(files, nil, jobs: 2)
        abort "worker did not fail"
      rescue Crap4Ruby::Error
      end
      puts JSON.generate(exit_hook: File.exist?(marker))
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { exit_hook: bool }
      result = JSON.parse(output, symbolize_names: true)

      refute result.fetch(:exit_hook)
      assert_empty error
    end
  end

  def test_cli_workers_preserve_reports_snapshots_and_threshold_statuses
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~'RUBY') do |output, error, status|
      require "stringio"
      files.each { |path| File.write(path, "def pick(x)\n x ||= 1\n x\nend\n") }
      report = File.join(root, "result.json")
      File.write(report, JSON.generate("Test" => {"coverage" => {
        files[0] => [1, 1, 0, nil], files[1] => [1, 1, 1, nil]
      }}))
      cases = [["--coverage", report, "--threshold", "3"], ["--coverage", report, "--threshold", "2"],
        ["--no-coverage", "--threshold", "1"]]
      results = [1, 2].map do |jobs|
        cases.map do |arguments|
          out, err = StringIO.new, StringIO.new
          status = Crap4Ruby::CLI.new(stdout: out, stderr: err).run(
            ["--root", root, "--jobs", jobs.to_s, *arguments, *files])
          [status, out.string, err.string, File.read(File.join(root, ".metrics/crap.edn"))]
        end
      end
      puts JSON.generate(equal: results[0] == results[1], statuses: results[1].map(&:first))
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { equal: bool, statuses: Array[Integer] }
      result = JSON.parse(output, symbolize_names: true)

      assert result.fetch(:equal)
      assert_equal [0, 2, 1], result.fetch(:statuses)
    end
  end

  def test_cli_worker_failures_preserve_the_previous_snapshot
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      require "stringio"
      FileUtils.mkdir_p(File.join(root, ".metrics"))
      snapshot = File.join(root, ".metrics/crap.edn")
      File.write(snapshot, "previous snapshot")
      File.write(files[0], "def broken(")
      out, err = StringIO.new, StringIO.new
      status = Crap4Ruby::CLI.new(stdout: out, stderr: err).run(
        ["--root", root, "--no-coverage", "--jobs", "2", *files])
      abort "parse error contract changed" unless status == 1 && out.string.empty? && err.string.include?("second.rb:")
      abort "parse error replaced snapshot" unless File.read(snapshot) == "previous snapshot"
      File.write(files[0], "def second = 2")
      parent = Process.pid
      Crap4Ruby::Analyzer.prepend(Module.new do
        define_method(:call) do |source, path:|
          Process.exit!(17) unless Process.pid == parent
          super(source, path: path)
        end
      end)
      out, err = StringIO.new, StringIO.new
      status = Crap4Ruby::CLI.new(stdout: out, stderr: err).run(
        ["--root", root, "--no-coverage", "--jobs", "2", *files])
      puts JSON.generate(status: status, output: out.string, error: err.string, snapshot: File.read(snapshot))
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { status: Integer, output: String, error: String, snapshot: String }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal 1, result.fetch(:status)
      assert_empty result.fetch(:output)
      assert_match(/worker failed/, result.fetch(:error))
      assert_equal "previous snapshot", result.fetch(:snapshot)
    end
  end

  def test_external_child_reaper_does_not_break_results_or_receive_signals
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      signals = []
      Process.define_singleton_method(:kill) { |signal, pid| signals << [signal, pid]; 0 }
      Signal.trap("CHLD") do
        begin
          loop { break unless Process.wait(-1, Process::WNOHANG) }
        rescue Errno::ECHILD
        end
      end
      Crap4Ruby::Batch.singleton_class.prepend(Module.new do
        def receive(worker)
          sleep(0.05)
          super
        end
      end)
      failure = nil
      entries = []
      begin
        entries = Crap4Ruby::Batch.call(files, nil, jobs: 2)
      rescue StandardError => error
        failure = error.class.name
      end
      puts JSON.generate(failure: failure, signals: signals.size, names: entries.map(&:name))
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { failure: String?, signals: Integer, names: Array[String] }
      result = JSON.parse(output, symbolize_names: true)

      assert_nil result.fetch(:failure)
      assert_equal 0, result.fetch(:signals)
      assert_equal %w[second first], result.fetch(:names)
    end
  end

  def test_interrupt_after_wait_does_not_signal_a_reaped_pid
    skip "fork is unavailable" unless Process.respond_to?(:fork)

    run_program(<<~RUBY) do |output, error, status|
      signals = []
      Process.define_singleton_method(:kill) { |signal, pid| signals << [signal, pid]; 0 }
      Process.singleton_class.prepend(Module.new do
        def wait2(pid, flags = 0)
          result = super
          unless @interrupted
            @interrupted = true
            raise Interrupt
          end
          result
        end
      end)
      begin
        Crap4Ruby::Batch.call(files, nil, jobs: 2)
        abort "analysis was not interrupted"
      rescue Interrupt
      end
      puts JSON.generate(signals: signals.size)
    RUBY
      assert status.success?, "#{output}\n#{error}"
      # @type var result: { signals: Integer }
      result = JSON.parse(output, symbolize_names: true)

      assert_equal 0, result.fetch(:signals)
    end
  end
end
