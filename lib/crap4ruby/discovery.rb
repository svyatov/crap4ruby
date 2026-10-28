# frozen_string_literal: true

require "find"
require "open3"

module Crap4Ruby
  module Discovery
    EXCLUDED = %w[test tests spec features vendor node_modules target coverage tmp log pkg build dist].freeze

    def self.call(root:, source_roots:, paths:, changed:)
      existing, filters = paths.partition { |path| File.exist?(File.expand_path(path, root)) }
      roots = source_roots.map do |path|
        directory = File.expand_path(path, root)
        raise Error, "#{path}: source root must be a directory" unless File.directory?(directory)

        directory
      end
      roots.concat(existing.map { |path| File.expand_path(path, root) })
      roots << root if roots.empty?
      files = roots.flat_map { |path| File.file?(path) ? [path] : walk(path) }
      files = files.select { |path| File.extname(path) == ".rb" }.map { |path| File.realpath(path) }.uniq.sort
      files.select! { |path| filters.any? { |filter| path.delete_prefix("#{root}/").include?(filter) } } unless filters.empty?
      files &= changed_files(root) if changed
      files
    end

    def self.walk(root)
      paths = []
      Find.find(root) do |path|
        name = File.basename(path)
        if File.directory?(path)
          Find.prune if path != root && (name.start_with?(".") || EXCLUDED.include?(name) || File.symlink?(path))
        elsif !File.symlink?(path) && !name.start_with?(".") && !name.match?(/\A(?:test|spec)_|_(?:test|spec)\.rb\z/)
          paths << path
        end
      end
      paths
    end

    def self.git(root, *arguments)
      output, error, status = Open3.capture3("git", "-C", root, *arguments)
      raise Error, "git: #{error.strip}" unless status.success?

      output
    end

    def self.changed_files(root)
      top = git(root, "rev-parse", "--show-toplevel").chomp
      git(root, "status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all", "--", ".")
        .split("\0").filter_map do |entry|
          path = File.join(top, entry[3..])
          File.realpath(path) if File.file?(path)
        end
    end
  end
end
