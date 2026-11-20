# frozen_string_literal: true

module Crap4Ruby
  # Pairs report definitions and applies the comparison policy to the resulting changes.
  module BaselineComparison
    # One pair, addition, removal, or ambiguous group, with its gate outcome.
    Finding = Data.define(:kind, :base, :head, :status)

    # A comparison with the revisions and exact policy values used to compute it.
    Result = Data.define(:base_revision, :head_revision, :limit, :min_increase, :findings, :status)

    # @!parse
    #   class Crap4Ruby::BaselineComparison::Finding
    #     # @return [Symbol] the matching outcome
    #     attr_reader :kind
    #     # @return [Array<BaselineEntry>] definitions before the change
    #     attr_reader :base
    #     # @return [Array<BaselineEntry>] definitions after the change
    #     attr_reader :head
    #     # @return [Integer] gate exit code for this finding
    #     attr_reader :status
    #   end
    #   class Crap4Ruby::BaselineComparison::Result
    #     # @return [String] base revision
    #     attr_reader :base_revision
    #     # @return [String] head revision
    #     attr_reader :head_revision
    #     # @return [Rational] exclusive score limit
    #     attr_reader :limit
    #     # @return [Rational] exclusive increase limit for matched scores
    #     attr_reader :min_increase
    #     # @return [Array<Finding>] outcomes for all definitions
    #     attr_reader :findings
    #     # @return [Integer] 2 for a violation, 1 for uncertainty, or 0 otherwise
    #     attr_reader :status
    #   end

    # Pairs definitions from compatible reports and evaluates the gate.
    # @param base [BaselineReport] report for the base revision
    # @param head [BaselineReport] report for the head revision
    # @param limit [Rational] exclusive score limit
    # @param min_increase [Rational] exclusive increase limit for matched scores
    # @return [Result] shared input for the Markdown renderer and gate exit status
    def self.call(base, head, limit:, min_increase:)
      before = base.entries.group_by { |entry| identity(entry) }
      after = head.entries.group_by { |entry| identity(entry) }
      findings = (before.keys | after.keys).sort.flat_map do |key|
        compare_identity(before.fetch(key, []), after.fetch(key, []), limit, min_increase)
      end
      Result.new(base.revision, head.revision, limit, min_increase, findings, findings.map(&:status).max || 0)
    end

    # Formats a comparison as a GitHub job summary with the gate outcome in either mode.
    # @param result [Result] output from comparing two reports
    # @param enforced [Boolean] whether the caller will use the outcome as its exit status
    # @return [String] Markdown comparison, ending with a newline
    def self.markdown(result, enforced:)
      BaselineMarkdown.render(result, enforced: enforced)
    end

    def self.identity(entry)
      [entry.namespace, entry.kind, entry.name]
    end

    def self.compare_identity(base, head, limit, min_increase)
      before = base.group_by(&:path)
      after = head.group_by(&:path)
      same_path = (before.keys & after.keys).sort.filter_map do |path|
        old = before.fetch(path)
        current = after.fetch(path)
        next unless unique_pair?(old, current)

        before.delete(path)
        after.delete(path)
        matched(old.fetch(0), current.fetch(0), limit, min_increase)
      end
      same_path + compare_remaining(before.values.flatten(1), after.values.flatten(1), limit, min_increase)
    end

    def self.compare_remaining(base, head, limit, min_increase)
      return head.map { |entry| added(entry, limit) } if base.empty?
      return base.map { |entry| Finding.new(:removed, [entry], [], 0) } if head.empty?
      return [matched(base.fetch(0), head.fetch(0), limit, min_increase)] if unique_pair?(base, head)

      [ambiguous(base, head, limit)]
    end

    def self.unique_pair?(base, head)
      base.size == 1 && head.size == 1
    end

    def self.matched(base, head, limit, min_increase)
      baseline = base.crap
      score = head.crap
      status = baseline ? matched_status(baseline, head, score, limit, min_increase) : 0
      Finding.new(:matched, [base], [head], status)
    end

    def self.matched_status(baseline, head, score, limit, min_increase)
      return upper_bound(head) > limit ? 1 : 0 unless score

      score > limit && score - baseline > min_increase ? 2 : 0
    end

    def self.added(head, limit)
      score = head.crap
      status =
        if score
          score > limit ? 2 : 0
        else
          upper_bound(head) > limit ? 1 : 0
        end
      Finding.new(:added, [], [head], status)
    end

    def self.ambiguous(base, head, limit)
      before = base.map { |entry| measurements_at_path(entry) }.tally
      after = head.map { |entry| measurements_at_path(entry) }.tally
      return Finding.new(:ambiguous_unchanged, base, head, 0) if before == after

      status = head.any? { |entry| (entry.crap || upper_bound(entry)) > limit } ? 1 : 0
      Finding.new(:ambiguous_changed, base, head, status)
    end

    # Compares a definition's location and measurements independently of its declaration line.
    # @param entry [BaselineEntry] method definition
    # @return [Array] path, complexity, exact CRAP, coverage, and coverage reason
    def self.measurements_at_path(entry)
      [entry.path, entry.complexity, entry.crap, entry.coverage, entry.coverage_note]
    end

    # Calculates the maximum CRAP score, attained at zero coverage.
    # @param entry [BaselineEntry] method definition
    # @return [Integer] upper bound used when a score is unknown
    def self.upper_bound(entry)
      complexity = entry.complexity
      (complexity * complexity) + complexity
    end

    private_class_method :identity, :compare_identity, :compare_remaining, :unique_pair?, :matched, :matched_status,
      :added, :ambiguous
  end
end
