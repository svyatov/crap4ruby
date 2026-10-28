# frozen_string_literal: true

require "rake/testtask"

task :prepare_coverage do
  FileUtils.rm_f(File.expand_path("coverage/.resultset.json", __dir__))
end

Rake::TestTask.new(test: :prepare_coverage) do |task|
  task.libs << "test"
  task.pattern = "test/**/*_test.rb"
end

task default: :test
