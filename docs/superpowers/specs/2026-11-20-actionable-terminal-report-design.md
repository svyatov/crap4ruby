# Actionable terminal report

## Intent

Help developers find a method from the terminal report and understand the coverage data behind its score.

## Approaches

1. O1, selected by the user. Show a short coverage reason for each affected method. This puts the next diagnostic step beside the result.
2. O2. Show only the count of unknown scores. This keeps the table narrower and leaves each cause for the developer to investigate.

## Behavior

- Show each displayed method's declaration as a path and line relative to the analysis root. For a literal `define_method`, use the call's first line. Collect the location in both coverage modes.
- Show the number of source files and methods analyzed, the count of measured scores strictly above the display threshold, and the count of unknown scores. Show the SimpleCov resultset path, `Coverage disabled`, or that an empty selection needed no resultset.
- In coverage-enabled runs, put a short reason in the coverage column. Distinguish a body that shares the declaration line, trailing code on a selected body line, and a resultset with no measurable lines for the method. For a method assigned zero coverage because its file is missing from the resultset, mark the zero as `file absent from report`.
- With `--no-coverage`, show `N/A` in the cells and explain the disabled coverage once in the summary. Sort the terminal rows by descending cyclomatic complexity, using the established ordering for ties.

## Constraints

Keep the current default filter, `--verbose`, measured score calculations, coverage states, threshold exit codes, and EDN snapshot format and ordering. Apply complexity ordering only to the terminal view. Keep empty selections distinct from scans with no scores above the display threshold.

## Verification

Use CLI regression tests for source locations, summary counts, reason labels, complexity ordering, `--verbose`, and empty selections. Check that snapshots and threshold exit codes retain their documented behavior. The implementation can choose the exact summary wording and table alignment.
