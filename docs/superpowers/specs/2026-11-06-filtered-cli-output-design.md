# Filtered CLI output

## Intent and scope

Reduce terminal output for large projects by showing methods that need attention. This is a small CLI presentation change.

## Approaches

1. O1, selected by the user: show scores above the display limit and all unknown scores. Missing coverage remains visible.
2. O2: show only known scores above the display limit. This produces less output but can hide missing coverage.

Both approaches provide `--verbose` for the complete method table. The user selected O1 to retain unknown scores in normal output.

## Behavior

The default display limit is 30. When `--threshold N` is supplied, N also becomes the display limit.

Normal output includes methods whose unrounded CRAP score strictly exceeds the display limit, plus every method whose score is unknown. Preserve report ordering.

Add `--verbose` to show every analyzed method. Preserve `-v` as the version option.

When no methods are selected for display, print a short message stating that no methods exceed the display limit. Distinguish an empty analysis selection.

With `--no-coverage`, every score is unknown, so every method remains visible under O1.

## Constraints and non-goals

The default display limit does not enable threshold enforcement. Only an explicit `--threshold` affects threshold exit statuses.

Evaluate threshold checks and write snapshots using all analyzed methods. Preserve diagnostics, scoring, coverage handling, and `--no-save` behavior.

Do not introduce a project score, dependency, configuration file, or new short option. Do not truncate unknown scores or silently treat them as passing.

## Verification and builder decisions

Test the default limit, explicit limits, exact boundary comparisons, unknown scores, verbose output, and empty display and analysis selections.

Verify that snapshots contain hidden methods and that filtering preserves threshold exit statuses. Update help, README examples, and affected type signatures.

The builder chooses the short empty-result messages and the smallest reporting interface that supports this behavior.
