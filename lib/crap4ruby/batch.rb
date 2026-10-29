# frozen_string_literal: true

require "etc"

module Crap4Ruby
  # Analyzes selected files and scores their methods in input order.
  module Batch
    # Reads Ruby source without executing it and preserves method order per file.
    #
    # @param files [Array<String>] source paths in analysis order
    # @param coverage [Coverage, nil] measured coverage, or nil for complexity only
    # @param jobs [Integer, nil] worker count, or nil for automatic selection
    # @return [Array<Entry>] scored methods in file and traversal order
    # @raise [ArgumentError] if the requested worker count is not positive
    def self.call(files, coverage, jobs: nil)
      raise ArgumentError, "jobs must be positive" if jobs && jobs < 1

      count = worker_count(files.size, jobs)
      count > 1 ? parallel(files, coverage, count) : serial(files, coverage)
    end

    class << self
      private

      def worker_count(size, jobs)
        return 1 if size < 2 || jobs == 1 || (!jobs && size < 64)
        return 1 unless Process.respond_to?(:fork) && Thread.list.one?

        [size, jobs || [4, Etc.nprocessors].min].min
      end

      def serial(files, coverage)
        analyzer = Analyzer.new(coverage: !coverage.nil?)
        files.flat_map do |path|
          analyzer.call(File.binread(path), path: path).map { |method| Score.call(method, coverage) }
        end
      end

      def parallel(files, coverage, count)
        # @type var workers: Array[worker]
        workers = [] #: Array[worker]
        begin
          files.each_slice((files.size + count - 1) / count) do |chunk|
            Thread.handle_interrupt(Exception => :never) { start_worker(chunk, coverage, workers) }
          end
        rescue NotImplementedError, Errno::EAGAIN, Errno::ENOMEM, Errno::EMFILE, Errno::ENFILE
          cleanup(workers)
          return serial(files, coverage)
        end
        results = workers.map { |worker| receive(worker) }
        results.flat_map do |result|
          raise result if result.is_a?(StandardError)

          result
        end
      ensure
        cleanup(workers)
      end

      def start_worker(files, coverage, workers)
        # @type var pipes: Array[IO]
        pipes = []
        pid = nil #: Integer?
        begin
          2.times { pipes.concat(IO.pipe) }
          pid = Process.fork do
            run_child(pipes, files, coverage, workers)
          end
          workers << [pipes.fetch(0), pid, pipes.fetch(3)]
        ensure
          close_pipe(pipes[1])
          close_pipe(pipes[2])
          unless pid
            close_pipe(pipes[0])
            close_pipe(pipes[3])
          end
        end
      end

      def run_child(pipes, files, coverage, workers)
        # @type var status: Integer
        status = 1
        workers.each do |worker|
          close_pipe(worker[0])
          close_pipe(worker[2])
        end
        close_pipe(pipes.fetch(0))
        close_pipe(pipes.fetch(3))
        cancellation = pipes.fetch(2)
        Thread.new do
          cancellation.read
          Process.exit!(1)
        end
        result = child_result(files, coverage)
        Marshal.dump(result, pipes.fetch(1))
        status = 0
      ensure
        begin
          close_pipe(pipes[1])
        ensure
          Process.exit!(status)
        end
      end

      def child_result(files, coverage)
        serial(files, coverage)
      rescue StandardError => error
        error
      end

      def receive(worker)
        # @type var reader: IO
        reader = worker[0]
        data = reader.read
        status = reap(worker)
        if status && !status.success?
          raise Error,
            "analysis worker failed (exit #{status.exitstatus || "signal #{status.termsig}"})"
        end

        payload = decode(data)
        return payload if payload.is_a?(StandardError)
        return payload if payload.is_a?(Array) && payload.all?(Entry)

        raise Error, "analysis worker returned invalid results"
      rescue EOFError, TypeError, ArgumentError => error
        raise Error, "analysis worker returned an invalid payload: #{error.message}"
      ensure
        reader.close unless reader.closed?
      end

      def decode(data)
        # Only this call's child processes supply Marshal data; receive validates its shape.
        # rubocop:disable-next Security/MarshalLoad
        Marshal.load(data)
      end

      def cleanup(workers)
        Thread.handle_interrupt(Exception => :never) do
          workers.each do |worker|
            close_pipe(worker[2])
            close_pipe(worker[0])
          end
          # Close every cancellation channel before waiting for any worker.
          # rubocop:disable-next Style/CombinableLoops
          workers.each { |worker| reap(worker) }
        end
      end

      def reap(worker)
        pid = worker[1]
        return unless pid

        Thread.handle_interrupt(Exception => :never) do
          # @type var status: Process::Status?
          begin
            _, status = Process.wait2(pid)
          rescue Errno::ECHILD
            # A host's SIGCHLD handler may have consumed the exit status.
            status = nil
          end
          worker[1] = nil
          status
        end
      end

      def close_pipe(pipe)
        pipe.close if pipe && !pipe.closed?
      end
    end
  end
end
