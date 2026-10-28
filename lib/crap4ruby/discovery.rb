# frozen_string_literal: true

require "find"
require "open3"

module Crap4Ruby
  # Selects Ruby source files from explicit paths, directories, and Git changes.
  module Discovery
    # Directory names excluded during recursive traversal.
    EXCLUDED = %w[test tests spec features vendor node_modules target coverage tmp log pkg build dist].freeze

    # Combines source roots and existing paths, then applies filters and Git selection.
    # Explicit files bypass traversal exclusions but must have the `.rb` extension.
    # Defaults to the project root when no source roots or existing paths are given.
    #
    # @param root [String] absolute project directory
    # @param source_roots [Array<String>] source directories, absolute or relative to root
    # @param paths [Array<String>] existing paths or substring filters relative to root
    # @param changed [Boolean] restrict results to staged, unstaged, and untracked files
    # @return [Array<String>] sorted, unique real paths; substring filters use OR
    # @raise [Error] if a source root is not a directory or Git fails
    # @raise [SystemCallError] if paths cannot be read or resolved
    def self.call(root:, source_roots:, paths:, changed:)
      existing, filters = paths.partition { |path| File.exist?(File.expand_path(path, root)) }
      roots = selection_roots(root, source_roots, existing)
      files = roots.flat_map { |path| File.file?(path) ? [path] : walk(path) }
      files = files.select { |path| File.extname(path) == ".rb" }.map { |path| File.realpath(path) }.uniq.sort
      unless filters.empty?
        files.select! do |path|
          filters.any? do |filter|
            path.delete_prefix("#{root}/").include?(filter)
          end
        end
      end
      files &= changed_files(root) if changed
      files
    end

    # Validates directory roots and combines them with explicit paths.
    #
    # @param root [String] absolute project directory
    # @param source_roots [Array<String>] explicit source directories
    # @param existing [Array<String>] existing positional paths
    # @return [Array<String>] expanded roots, defaulting to the project directory
    def self.selection_roots(root, source_roots, existing)
      roots = source_roots.map do |path|
        directory = File.expand_path(path, root)
        raise Error, "#{path}: source root must be a directory" unless File.directory?(directory)

        directory
      end
      roots.concat(existing.map { |path| File.expand_path(path, root) })
      roots << root if roots.empty?
      roots
    end

    # Walks a directory without following symlinks or entering excluded directories.
    # Hidden files and test/spec filenames are excluded; extensions are not filtered.
    #
    # @param root [String] directory to traverse, including an explicitly selected hidden directory
    # @return [Array<String>] candidate file paths in traversal order
    # @raise [SystemCallError] if traversal fails
    def self.walk(root)
      paths = [] #: Array[String]
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

    # Runs Git in the project directory without a shell.
    #
    # @param root [String] working directory for Git
    # @param arguments [Array<String>] command and arguments
    # @return [String] standard output, preserving NUL separators
    # @raise [Error] if Git exits unsuccessfully
    # @raise [SystemCallError] if Git cannot be started
    def self.git(root, *arguments)
      output, error, status = Open3.capture3("git", "-C", root, *arguments)
      raise Error, "git: #{error.strip}" unless status.success?

      output
    end

    # Finds existing staged, unstaged, and untracked files under the project directory.
    # Deleted files are omitted and renames are treated as deletion and addition.
    #
    # @param root [String] directory inside a Git working tree
    # @return [Array<String>] real paths, without extension or traversal filtering
    # @raise [Error] if Git cannot inspect the working tree
    # @raise [SystemCallError] if Git cannot start or a path cannot be resolved
    def self.changed_files(root)
      top = git(root, "rev-parse", "--show-toplevel").chomp
      git(root, "status", "--porcelain=v1", "-z", "--no-renames", "--untracked-files=all", "--", ".")
        .split("\0").filter_map do |entry|
          path = File.join(top, entry[3..].to_s)
          File.realpath(path) if File.file?(path)
        end
    end
  end
end
