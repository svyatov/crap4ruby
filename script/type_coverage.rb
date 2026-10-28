# frozen_string_literal: true

require "csv"
require "open3"

module TypeCoverage
  HEADER = ["Target", "File", "Status", "Typed calls", "Untyped calls", "All calls", "Typed %"].freeze

  def self.failures(csv, sources)
    rows = CSV.parse(csv) || []
    raise ArgumentError, "Unexpected Steep stats header" unless rows.shift == HEADER

    files = rows.map { |row| row.fetch(1).to_s }
    errors = (sources - files).map { |path| "#{path}: not checked" }
    errors.concat((files - sources).map { |path| "#{path}: unexpected file" })
    files.tally.each { |path, count| errors << "#{path}: checked more than once" if count > 1 }
    rows.each do |row|
      typed = Integer(row.fetch(3).to_s, 10)
      untyped = Integer(row.fetch(4).to_s, 10)
      total = Integer(row.fetch(5).to_s, 10)
      unless row.fetch(2) == "success" && typed >= 0 && untyped.zero? && typed == total
        errors << "#{row.fetch(1)}: requires 100% typed calls (#{typed}/#{total}, #{untyped} untyped)"
      end
    end
    errors
  end

  def self.sources
    output, status = Open3.capture2("git", "ls-files", "--cached", "--others", "--exclude-standard", "-z")
    raise "Cannot list repository files" unless status.success?

    output.split("\0").uniq.select do |path|
      path.match?(/\.(?:rb|rake|gemspec)\z/) || %w[Gemfile Rakefile Steepfile].include?(File.basename(path)) || path.start_with?("exe/", "bin/")
    end
  end

  def self.run
    output, status = Open3.capture2("bundle", "exec", "steep", "stats", "--format=csv", "-j", "2")
    return 1 unless status.success?

    files = sources
    errors = failures(output, files)
    Dir["sig/**/*.rbs", "sig-development/**/*.rbs"].each do |path|
      errors << "#{path}: untyped signatures are forbidden" if File.read(path).match?(/\buntyped\b/)
    end
    if errors.empty?
      puts "Type coverage: 100% across all #{files.size} Ruby files"
      0
    else
      warn errors.join("\n")
      1
    end
  end
end

exit TypeCoverage.run if $PROGRAM_NAME == __FILE__
