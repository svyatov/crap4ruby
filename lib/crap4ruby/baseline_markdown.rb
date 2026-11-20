# frozen_string_literal: true

module Crap4Ruby
  # Renders a baseline comparison for human review.
  module BaselineMarkdown
    VERDICTS = ["pass", "uncertain", "measured violations"].freeze
    FINDING_LIMIT = 50
    LEGACY_LIMIT = 10
    GROUP_MEMBER_LIMIT = 5
    FIELD_LIMIT = 120
    AMBIGUOUS = %i[ambiguous_changed ambiguous_unchanged].freeze
    TABLE_HEADER = "| Finding | Method | Location | CRAP | Complexity | Coverage |\n" \
                   "| --- | --- | --- | --- | --- | --- |\n"
    private_constant :VERDICTS, :FINDING_LIMIT, :LEGACY_LIMIT, :GROUP_MEMBER_LIMIT, :FIELD_LIMIT, :AMBIGUOUS,
      :TABLE_HEADER

    # Formats a comparison as a GitHub job summary, including the gate outcome in either mode.
    # @param result [BaselineComparison::Result] output from comparing two reports
    # @param enforced [Boolean] whether the caller will use the outcome as its exit status
    # @return [String] Markdown comparison, ending with a newline
    def self.render(result, enforced:)
      findings = result.findings
      mode = enforced ? "enforced" : "report only"
      text = +"## CRAP comparison\n\n"
      text << "Base `#{result.base_revision}` → head `#{result.head_revision}`\n\n"
      text << "CRAP limit: #{exact_number(result.limit)} · Minimum increase: #{exact_number(result.min_increase)}\n\n"
      text << "**Verdict: #{VERDICTS.fetch(result.status)} (#{mode}).**\n\n"
      text << summary(findings)
      text << "\nScores and coverage are rounded for display. The gate uses exact scores.\n" unless findings.empty?
      text << finding_details(findings)
      text << existing_scores(findings, result.limit)
    end

    def self.summary(findings)
      "Additions: #{findings.count { |finding| finding.kind == :added }} · " \
        "removals: #{findings.count { |finding| finding.kind == :removed }} · " \
        "improvements: #{findings.count { |finding| improved?(finding) }} · " \
        "unavailable comparisons: #{findings.count { |finding| unavailable?(finding) }}\n"
    end

    def self.improved?(finding)
      return false unless finding.kind == :matched

      before = finding.base.fetch(0).crap
      after = finding.head.fetch(0).crap
      !before.nil? && !after.nil? && after < before
    end

    def self.unavailable?(finding)
      case finding.kind
      when :added then finding.head.fetch(0).crap.nil?
      when :matched then finding.base.fetch(0).crap.nil? || finding.head.fetch(0).crap.nil?
      when :removed then false
      else true
      end
    end

    def self.moved?(finding)
      finding.kind == :matched && finding.base.fetch(0).path != finding.head.fetch(0).path
    end

    def self.visible?(finding)
      return true unless finding.kind == :matched
      return true if unavailable?(finding)

      BaselineComparison.measurements_at_path(finding.base.fetch(0)) !=
        BaselineComparison.measurements_at_path(finding.head.fetch(0))
    end

    def self.finding_details(findings)
      visible = findings.select { |finding| visible?(finding) }
      ordered = visible.each_with_index.sort_by { |finding, index| [-finding.status, moved?(finding) ? 0 : 1, index] }
      return "" if ordered.empty?

      groups, single = ordered.take(FINDING_LIMIT).map(&:first).partition { |finding| AMBIGUOUS.include?(finding.kind) }
      group_rows = groups.map { |group| group_details(group) }.join
      table(single) + group_rows + omitted(ordered.size, FINDING_LIMIT, "findings")
    end

    def self.existing_scores(findings, limit)
      # @type var scores: Array[[Rational, BaselineComparison::Finding]]
      scores = findings.filter_map do |finding|
        score = finding.head.first&.crap
        [score, finding] if finding.kind == :matched && finding.status.zero? && score && score > limit
      end
      return "" if scores.empty?

      ranked = scores.sort_by { |score, _finding| -score }
      visible = ranked.take(LEGACY_LIMIT).map(&:last)
      "\n<details>\n<summary>Existing high scores (#{visible.size} of #{ranked.size} shown)</summary>\n" \
        "#{table(visible)}\n</details>\n"
    end

    def self.table(findings)
      return "" if findings.empty?

      "\n#{TABLE_HEADER}#{findings.map { |finding| table_row(finding) }.join}"
    end

    def self.table_row(finding)
      base = finding.base.first
      head = finding.head.first
      method = method_label(head || finding.base.fetch(0))
      cells = [finding_label(finding), method,
        before_after(base, head) { |entry| location(entry) },
        score_change(base, head),
        before_after(base, head) { |entry| entry.complexity.to_s },
        before_after(base, head) { |entry| coverage_text(entry) }]
      "| #{cells.join(" | ")} |\n"
    end

    def self.finding_label(finding)
      label =
        case finding.kind
        when :added then "Added"
        when :removed then "Removed"
        else matched_label(finding)
        end
      case finding.status
      when 2 then "#{label} (violation)"
      when 1 then "#{label} (uncertain)"
      else label
      end
    end

    def self.matched_label(finding)
      return "Moved" if moved?(finding)
      return "Measurement unavailable" if unavailable?(finding)
      return "Improved" if improved?(finding)
      return "Changed" if visible?(finding)

      "Existing"
    end

    def self.before_after(base, head)
      before = base ? yield(base) : "-"
      after = head ? yield(head) : "-"
      before == after ? after : "#{before} → #{after}"
    end

    def self.score_change(base, head)
      before = base&.crap
      after = head&.crap
      if before && after && before != after
        "#{score_text(before)} → #{score_text(after)} (#{format("%+.2f", after - before)})"
      else
        before_after(base, head) { |entry| score_text(entry.crap) }
      end
    end

    def self.group_details(finding)
      change = finding.kind == :ambiguous_changed ? "changed" : "unchanged"
      outcome = finding.status == 1 ? " (uncertain)" : ""
      method = method_label(finding.head.fetch(0))
      "\n**Ambiguous group #{change}#{outcome}: #{method}**\n" \
        "#{group_members("Base", finding.base)}#{group_members("Head", finding.head)}"
    end

    def self.group_members(side, entries)
      visible = entries.sort_by do |entry|
        risk = entry.crap || BaselineComparison.upper_bound(entry)
        [-risk, entry.path, entry.line]
      end.take(GROUP_MEMBER_LIMIT)
      rows = visible.map do |entry|
        "- #{location(entry)} · CRAP #{score_text(entry.crap)} · " \
          "CC #{entry.complexity} · Coverage #{coverage_text(entry)}\n"
      end
      "\n#{side} (#{visible.size} of #{entries.size} shown)\n\n#{rows.join}"
    end

    def self.omitted(count, limit, noun)
      count > limit ? "\n#{count - limit} more #{noun} omitted.\n" : ""
    end

    def self.method_label(entry)
      separator = entry.kind == "singleton" ? "." : "#"
      "#{literal(entry.namespace)}#{separator}#{literal(entry.name)}"
    end

    def self.location(entry)
      "#{literal(entry.path)}:#{entry.line}"
    end

    def self.score_text(value)
      return "unknown" unless value

      value.denominator == 1 ? value.numerator.to_s : format("%.2f", value)
    end

    def self.exact_number(value)
      value.denominator == 1 ? value.numerator.to_s : value.to_s
    end

    def self.coverage_text(entry)
      note = entry.coverage_note
      description = literal(Report::COVERAGE_NOTES.fetch(note.to_sym, note)) if note
      coverage = entry.coverage
      if coverage
        percentage = format("%.1f%%", coverage)
        return description ? "#{percentage} (#{description})" : percentage
      end

      "unknown (#{description || "no reason supplied"}, upper bound #{BaselineComparison.upper_bound(entry)})"
    end

    def self.literal(value)
      text = value.length > FIELD_LIMIT ? "#{value[0, FIELD_LIMIT]}…" : value
      escaped_controls = text.gsub(/[[:cntrl:]\p{Zl}\p{Zp}]/) { |character| format("\\u%04x", character.ord) }
      escaped_controls.gsub(/[&<>|`\\\[\]*_~@:]|www\./i) do |match|
        match.each_char.map { |character| "&##{character.ord};" }.join
      end
    end

    private_class_method :summary, :improved?, :unavailable?, :moved?, :visible?, :finding_details, :existing_scores,
      :table, :table_row, :finding_label, :matched_label, :before_after, :score_change, :group_details, :group_members,
      :omitted, :method_label, :location, :score_text, :exact_number, :coverage_text, :literal
  end
end
