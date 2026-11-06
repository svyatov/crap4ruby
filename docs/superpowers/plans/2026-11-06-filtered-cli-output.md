# Filtered CLI output implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show CRAP scores above 30 and unknown scores by default, with a complete table available through `--verbose`.

**Architecture:** Keep full entries in the CLI for snapshots and threshold checks. Filter only terminal output through a report formatter.

**Tech Stack:** Ruby, Minitest, RBS, and the repository's Rake checks. No added dependencies.

**Spec:** [Approved design](../specs/2026-11-06-filtered-cli-output-design.md).

## Global constraints

The default display limit is 30. An explicit `--threshold N` also sets the display limit.

Compare unrounded scores strictly above the limit. Always show unknown scores. Preserve `-v` as the version option.

Only explicit thresholds affect exit status. Preserve full snapshots, report ordering, diagnostics, and `--no-save` behavior.

## Review focus

- Decimal boundaries: scores equal to the limit are hidden, even if display rounding obscures differences.
- Unknown coverage: unknown scores remain visible with measured scores and with `--no-coverage`.
- Empty results: distinguish no analyzed methods from no scores above the limit.
- Verbose mode: display every method without changing snapshots or exit statuses.
- CLI compatibility: retain version output and coverage integration tests through explicit verbose requests where needed.

## Task 1: Filter terminal reports

**Files and responsibilities:**

- Modify `lib/crap4ruby/report.rb`: add `Report.terminal(entries, threshold: 30, verbose: false) -> String`; preserve `Report.table(entries)`.
- Modify `lib/crap4ruby/cli.rb`: parse `--verbose` and delegate terminal output with the explicit threshold or 30.
- Modify `sig/crap4ruby.rbs`: declare the formatter signature and optional `verbose` boolean in CLI options.
- Test `test/report_test.rb`, `test/cli_test.rb`, and `test/integration_test.rb`: verify filtering and preserve coverage assertions.
- Modify `README.md` and `CHANGELOG.md`: document display rules, verbose usage, and the change to normal output.

**Interfaces:** Consumes sorted `Array[Crap4Ruby::Entry]`. Produces a terminal string; full entries remain available for snapshots and enforcement.

- [x] Step 1: Add formatter tests with scores 29, 30, 30.01, and nil. Assert only 30.01 and nil appear by default, preserving order.
- [x] Step 2: Add explicit-limit tests using exact Rational boundaries. Assert equal scores are hidden and strictly greater scores remain visible.
- [x] Step 3: Add empty-result tests. Expect `No methods found.\n` for empty entries and `No methods exceed CRAP 30.\n` for filtered entries.
- [x] Step 4: Add verbose tests that compare terminal output with `Report.table(entries)`, including empty entries.
- [x] Step 5: Add CLI tests proving hidden methods remain in snapshots, default filtering exits 0, and explicit violations exit 2.
- [x] Step 6: Add CLI tests for `--verbose`, `-v`, unknown coverage, exact threshold boundaries, and `--no-save`.
- [x] Step 7: Run `bundle exec ruby -Itest test/report_test.rb` and `bundle exec ruby -Itest test/cli_test.rb`. Confirm new assertions fail before implementation.
- [x] Step 8: Implement the formatter and CLI delegation. Add matching YARD documentation and RBS signatures.
- [x] Step 9: Update integration tests that require complete measured rows to pass `--verbose`. Update empty-selection expectations.
- [x] Step 10: Document the display limit and explicit enforcement distinction. Keep the source-install sample consistent with default output.
- [x] Step 11: Run `bundle exec rake`. Require all lint, typing, test, CRAP, documentation, and audit checks to pass.
- [x] Step 12: Exercise the executable with normal, verbose, explicit-threshold, and no-coverage commands against temporary fixtures. Verify stdout and exit status.
- [x] Step 13: Review the complete diff against the approved design. Commit the behavior, tests, signatures, and documentation together.
