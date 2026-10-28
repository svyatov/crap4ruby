# frozen_string_literal: true

require "rake/testtask"
require "bundler"

# @type self: Rake::DSL

task :prepare_coverage do
  FileUtils.rm_f(File.expand_path("coverage/.resultset.json", File.dirname(__FILE__)))
end

Rake::TestTask.new(test: :prepare_coverage) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

desc "Run tests and require every library method's CRAP score to be at most 10"
task crap: :test do
  ruby "-Ilib", "exe/crap4ruby", "--source-root", "lib", "--threshold", "10"
end

desc "Check every Ruby file and require exactly 100% typed calls"
task :types do
  sh "bundle", "exec", "steep", "check", "-j", "2"
  ruby "script/type_coverage.rb"
end

task default: [:types, :crap]

desc "Refresh dependency locks and checksums for tests and release tools"
task :lock do
  bundler_version = Bundler.locked_gems.bundler_version.to_s
  abort "Run with Bundler #{bundler_version}" unless Bundler::VERSION == bundler_version
  Bundler.with_unbundled_env do
    %w[Gemfile gemfiles/release/Gemfile].each do |gemfile|
      sh({"BUNDLE_GEMFILE" => File.expand_path(gemfile, File.dirname(__FILE__))},
        "bundle", "lock", "--bundler", bundler_version,
        "--add-platform", "ruby", "x86_64-linux", "--add-checksums")
    end
  end
end
