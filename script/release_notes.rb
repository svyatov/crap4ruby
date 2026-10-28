# frozen_string_literal: true

require_relative "../lib/crap4ruby/version"

tag = ARGV.fetch(0)
abort "Tag #{tag} does not match version #{Crap4Ruby::VERSION}" unless tag == "v#{Crap4Ruby::VERSION}"

changelog = File.read(File.expand_path("../CHANGELOG.md", File.dirname(__FILE__)))
section = changelog.split(/^## /).find { |entry| entry.start_with?("[#{Crap4Ruby::VERSION}] - ") }
abort "Missing changelog entry for #{tag}" unless section

notes = section.lines.drop(1).take_while { |line| !line.start_with?("[Unreleased]:") }.join.strip
abort "Empty changelog entry for #{tag}" if notes.empty?

puts notes
