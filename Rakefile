# frozen_string_literal: true

require "rake/testtask"
require "bundler"
require "open3"

# @type self: Rake::DSL

desc "Check Ruby style, formatting, performance, and Minitest and Rake usage"
task :lint do
  sh "bundle", "exec", "rubocop"
end

desc "Apply safe Ruby style and formatting corrections"
task :format do
  sh "bundle", "exec", "rubocop", "--autocorrect"
end

desc "Check development and release dependencies against current security advisories"
task :audit do
  sh "bundle", "exec", "bundle-audit", "check", "--update", "--database", ".cache/ruby-advisory-db"
  sh "bundle", "exec", "bundle-audit", "check", "--gemfile-lock", "gemfiles/release/Gemfile.lock",
    "--database", ".cache/ruby-advisory-db"
end

desc "Remove stale coverage before running tests"
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

desc "Generate the YARD maintainer reference in doc/"
task :docs do
  sh "bundle", "exec", "yard", "doc"
end

desc "Check YARD syntax and require documentation for public library methods"
task :"docs:check" do
  sh "bundle", "exec", "yard", "doc", "--no-output"
  # YARD synthesizes reader descriptions; require source comments and explicit return types.
  query = "object.type == :method && object.visibility == :public && " \
          "(object.docstring.blank? || (object.is_attribute? && " \
          "(object.docstring.line_range.nil? || !object.tag(:return)&.types&.any?)))"
  output, status = Open3.capture2("bundle", "exec", "yard", "doc", "--list",
    "--query", query)
  abort "YARD documentation check failed" unless status.success?
  unless output.strip.empty?
    abort "Public methods or readers need YARD documentation and reader return types:\n#{output}"
  end
end

desc "Run all code quality checks"
task check: %i[lint types crap docs:check audit]

task default: :check

desc "Refresh dependency locks and checksums for tests and release tools"
task :lock do
  bundler_version = Bundler.locked_gems.bundler_version.to_s
  abort "Run with Bundler #{bundler_version}" unless bundler_version == Bundler::VERSION
  Bundler.with_unbundled_env do
    %w[Gemfile gemfiles/release/Gemfile].each do |gemfile|
      sh({"BUNDLE_GEMFILE" => File.expand_path(gemfile, File.dirname(__FILE__))},
        "bundle", "lock", "--bundler", bundler_version,
        "--add-platform", "ruby", "x86_64-linux", "--add-checksums")
    end
  end
end
