# frozen_string_literal: true

require "fileutils"
require "tempfile"

module Crap4Ruby
  module Report
    def self.sorted(entries)
      entries.sort_by { |entry| [entry.crap ? 0 : 1, -(entry.crap || 0), entry.namespace, entry.name, entry.path] }
    end

    def self.table(entries)
      rows = [["Function", "Namespace", "CC", "Cov%", "CRAP"]] + entries.map do |entry|
        [entry.name, entry.namespace, entry.complexity.to_s,
          entry.coverage ? format("%.1f%%", entry.coverage) : "N/A",
          entry.crap ? format("%.1f", entry.crap) : "N/A"]
      end
      widths = rows.transpose.map { |column| column.map(&:length).max }
      lines = rows.map do |row|
        row.each_with_index.map { |value, index| index < 2 ? value.ljust(widths[index]) : value.rjust(widths[index]) }.join("  ")
      end
      lines.insert(1, "-" * lines.first.length)
      (["CRAP Report", "==========="] + lines).join("\n") + "\n"
    end

    def self.edn(entries)
      rows = entries.map do |entry|
        "  {:name #{JSON.generate(entry.name)}, :namespace #{JSON.generate(entry.namespace)}, " \
          ":complexity #{entry.complexity}, :coverage #{number(entry.coverage)}, :crap #{number(entry.crap)}}"
      end
      rows.empty? ? "{:entries []}\n" : "{:entries [\n#{rows.join("\n")}\n]}\n"
    end

    def self.number(value)
      return "nil" if value.nil?

      text = format("%.4f", value).sub(/0+\z/, "")
      text.end_with?(".") ? "#{text}0" : text
    end

    def self.write(entries, root:)
      directory = File.join(root, ".metrics")
      FileUtils.mkdir_p(directory)
      path = File.join(directory, "crap.edn")
      Tempfile.create(["crap", ".edn"], directory) do |file|
        file.write(edn(entries))
        file.close
        File.rename(file.path, path)
      end
      path
    end
  end
end
