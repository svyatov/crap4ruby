# @type self: Steep::Project::DSL
target :library do
  check "lib", "exe/*"
  signature "sig"
  library "prism", "json", "optparse", "find", "open3", "fileutils", "tempfile"
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end

target :development do
  check "test", "script", "bin/*", "Rakefile", "Gemfile", "gemfiles/release/Gemfile", "crap4ruby.gemspec", "Steepfile"
  signature "sig", "sig-development"
  library "prism", "json", "optparse", "find", "open3", "fileutils", "tempfile",
    "tmpdir", "stringio", "shellwords", "coverage", "csv", "pathname"
  configure_code_diagnostics Steep::Diagnostic::Ruby.all_error
end
