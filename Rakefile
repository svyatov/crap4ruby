# frozen_string_literal: true

require "rake/testtask"

task :prepare_coverage do
  FileUtils.rm_f(File.expand_path("coverage/.resultset.json", __dir__))
end

Rake::TestTask.new(test: :prepare_coverage) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

desc "Run tests and require every library method's CRAP score to be at most 10"
task crap: :test do
  ruby "-Ilib", "exe/crap4ruby", "--source-root", "lib", "--threshold", "10"
end

task default: :crap
