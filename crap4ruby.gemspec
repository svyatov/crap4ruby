# frozen_string_literal: true

require_relative "lib/crap4ruby/version"

Gem::Specification.new do |spec|
  spec.name = "crap4ruby"
  spec.version = Crap4Ruby::VERSION
  spec.authors = ["Leonid Svyatov"]
  spec.summary = "CRAP scores for Ruby methods using Prism and SimpleCov reports"
  spec.description = "Static Ruby method complexity and test coverage combined into CRAP scores and crapper-compatible snapshots."
  spec.license = "MIT"
  spec.homepage = "https://github.com/svyatov/crap4ruby"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "bug_tracker_uri" => "#{spec.homepage}/issues",
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "rubygems_mfa_required" => "true",
    "allowed_push_host" => "https://rubygems.org"
  }
  spec.required_ruby_version = ">= 3.3"
  spec.files = Dir["lib/**/*.rb", "exe/*", "*.md", "LICENSE"]
  spec.require_paths = ["lib"]
  spec.bindir = "exe"
  spec.executables = ["crap4ruby"]
  spec.add_dependency "prism", ">= 1.0", "< 3"
end
