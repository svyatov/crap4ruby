# frozen_string_literal: true

require "digest"
require "rbconfig"
require "bundler"
require_relative "../lib/crap4ruby"

# Compare complete CLI latency without writing to the measured projects.
module PerformanceBenchmark
  def self.fingerprint(files)
    digest = Digest::SHA256.new
    files.each do |path|
      digest << path << "\0" << Digest::SHA256.file(path).hexdigest << "\0"
    end
    digest.hexdigest
  end

  def self.inputs(root, paths, coverage)
    files = Crap4Ruby::Discovery.call(root: root, source_roots: [], paths: paths, changed: false)
    files << File.join(root, "coverage/.resultset.json") if coverage
    [files.size - (coverage ? 1 : 0), fingerprint(files)]
  end

  def self.measure(library, root, paths, coverage)
    arguments = ["--root", root, "--no-save", *paths]
    arguments << "--no-coverage" unless coverage
    start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    # Gemfile evaluation preloads the candidate version. Give both copies a clean boot.
    # @type var result: [String, String, Process::Status]
    result = Bundler.with_unbundled_env do
      Open3.capture3(RbConfig.ruby, "-I", library, "-e", "gem 'prism', ARGV.shift; load ARGV.shift",
        Prism::VERSION, File.expand_path("../exe/crap4ruby", File.dirname(__FILE__)), *arguments)
    end
    output, error, status = result
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - start
    raise error unless status.success?

    [elapsed, Digest::SHA256.hexdigest(output)]
  end

  def self.project(root, libraries, count)
    root = File.realpath(root)
    paths = %w[app lib].select { |path| File.directory?(File.join(root, path)) }
    raise "#{root}: no app/ or lib/ directory" if paths.empty?

    records = [] #: Array[sample]
    modes = File.file?(File.join(root, "coverage/.resultset.json")) ? [false, true] : [false]
    modes.each do |coverage|
      files, input = inputs(root, paths, coverage)
      expected = nil #: String?
      (count + 1).times do |iteration|
        order = iteration.odd? ? libraries.reverse : libraries
        order.each do |name, library|
          raise "#{root}: inputs changed" unless inputs(root, paths, coverage) == [files, input]

          seconds, output = measure(library, root, paths, coverage)
          raise "#{root}: inputs changed" unless inputs(root, paths, coverage) == [files, input]

          expected ||= output
          raise "#{root}: reports differ" unless expected == output

          records << {project: root, coverage: coverage, files: files, input_sha256: input,
                      variant: name, warmup: iteration.zero?, seconds: seconds, output_sha256: output}
        end
      end
    end
    records
  end

  def self.run(arguments)
    baseline = arguments.shift
    raise "Usage: ruby script/benchmark.rb BASELINE_LIB PROJECT [PROJECT ...]" unless baseline && !arguments.empty?

    # @type var libraries: Array[[String, String]]
    libraries = [["baseline", File.realpath(baseline)],
      ["candidate", File.expand_path("../lib", File.dirname(__FILE__))]]
    libraries.each do |name, path|
      raise "#{name}: missing crap4ruby.rb" unless File.file?(File.join(path, "crap4ruby.rb"))
    end
    hashes = libraries.to_h { |name, path| [name, fingerprint(Dir[File.join(path, "**/*.rb")])] }
    count = Integer(ENV.fetch("SAMPLES", "7"), 10)
    raise "SAMPLES must be an odd integer of at least 3" unless count >= 3 && count.odd?

    samples = arguments.flat_map { |root| project(root, libraries, count) }
    libraries.each do |name, path|
      raise "#{name}: library changed" unless hashes[name] == fingerprint(Dir[File.join(path, "**/*.rb")])
    end
    puts JSON.pretty_generate(ruby: RUBY_DESCRIPTION, prism: Prism::VERSION, host: RbConfig::CONFIG["host"],
      library_sha256: hashes, samples: samples)
    samples.reject { |row| row[:warmup] }.group_by { |row| [row[:project], row[:coverage], row[:variant]] }
           .each do |key, rows|
             times = rows.map { |row| row[:seconds] }.sort
             warn "#{key.join(" ")}: median #{times.fetch(count / 2).round(4)}s, " \
                  "range #{times.fetch(0).round(4)}..#{times.fetch(count - 1).round(4)}s"
           end
  end
end

PerformanceBenchmark.run(ARGV) if $PROGRAM_NAME == __FILE__
