# Actionable terminal report implementation plan

> For agentic workers, use `superpowers:executing-plans` or `superpowers:subagent-driven-development`. Track each step with a checkbox.

**Goal.** Show where each method is declared and what the score measures.

**Architecture.** Carry declaration lines and coverage reasons from analysis to the terminal. Keep presentation decisions in `Report` and use the canonical list for snapshots and threshold checks.

**Tech stack.** Ruby 3.3+, Prism, SimpleCov, Minitest, RBS, and Steep.

**Spec.** [Actionable terminal report](../specs/2026-11-20-actionable-terminal-report-design.md).

## Global constraints

Keep current filtering, `--verbose`, scoring, coverage states, threshold exits, and EDN shape and order. Keep empty selections distinct from filtered results.

## Review focus

- A multiline `define_method` declaration points to the start of the call.
- A file missing from the resultset retains zero coverage where its body is measurable.
- Trailing source code and a declaration on the same line produce different reasons.
- A resultset with null body lines yields an unknown score.
- An empty scan does not require a SimpleCov file.

## Task 1. Add terminal context and coverage reasons

**Files.** Update the analyzer, coverage reader, scorer, entry records, CLI, report, RBS, tests, and README.

- [x] Add CLI assertions for the summary and `lib/sample.rb:2`, plus a fixture with a multiline literal `define_method`. Assert that a higher-complexity method precedes a lower-complexity method in terminal output while the snapshot keeps name order.
- [x] Add CLI assertions for `body shares declaration line`, `trailing code shares body line`, `no measurable lines in report`, and `file absent from report`. Check that measured zero and unknown scores remain distinct. Assert the coverage state for an empty selection.
- [x] Run `bundle exec ruby -Itest test/cli_test.rb` on Ruby 3.3. Expect the new assertions to fail on missing output.
- [x] Add a declaration line to `MethodInfo` and `Entry`. Carry an analysis or measurement reason only when there is a coverage exception. Return the fraction and reason from one coverage lookup.
- [x] Pass the selected file count, analysis root, and coverage state to the terminal reporter. Render locations, coverage notes, scan counts, and complexity-only ordering. Update RBS, YARD, and the README.
- [x] Run `bundle exec rake` on Ruby 3.3. Expect the full check to pass. Run the CLI with and without coverage using `--no-save` and inspect both outputs.
