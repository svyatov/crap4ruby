# Baseline comparison for pull requests

## Intent

Let a team review and enforce changes in method risk while making the high scores already present on its base branch visible. F2 uses the source locations and coverage reasons from F1. Develop F2 from the local F1 commit `80d4d19`.

## Approaches

1. O1, selected by the user. Export one report per revision and compare two report files. CI or the caller prepares each revision and its SimpleCov resultset. A report for the exact base commit can be reused with matching settings.
2. O2. Pass a Git ref to crap4ruby and have it prepare both revisions and run their tests. This reduces setup commands but makes the gem responsible for project dependencies and test environments.

## CLI

Use opt-in flags so an existing positional file or substring named `compare` keeps its meaning.

```sh
crap4ruby --json-report --revision "$BASE_SHA" --no-save > base.json
crap4ruby --json-report --revision "$HEAD_SHA" --no-save > head.json
crap4ruby --compare --base-report base.json --head-report head.json
crap4ruby --compare --base-report base.json --head-report head.json \
  --fail-on-regression --limit 30 --min-increase 1
```

The first two commands run in their respective source directories with coverage from those revisions. Keep JSON on stdout and diagnostics on stderr. `--no-save` controls the existing EDN write. The JSON export always includes every analyzed method in the selected scope. `--verbose` and the display threshold have no effect on that selection. An explicit `--threshold` still enforces the absolute limit and can return exit 1 or 2 with complete JSON. Keep ordinary CLI reports, scoring, and EDN compatible.

Report export accepts the default scan or explicit project-relative `--source-root` options. Reject `--changed`, positional selectors, `--no-coverage`, and source paths that resolve outside the analysis root in this mode. These restrictions apply to comparable JSON reports. Accept existing coverage path and coverage command options. Require a valid SimpleCov resultset when source files are selected. Record a zero-file scan as empty and allow it to be compared with a nonempty scan of the same scope. Preserve the error for a missing explicit source root. Use the default scan or a common parent when an entire source directory can appear or disappear between revisions.

The compare mode reads only the two JSON files and prints Markdown. It requires both paths. It rejects scan arguments and the absolute `--threshold` option. It does not run Git, tests, or write project metrics. Default the comparison limit to 30 and minimum increase to 1 in both report and gate modes. Accept finite nonnegative limits and compare exact values. CLI flag names and defaults in this section are proposed builder decisions.

## Report contract

Publish a versioned JSON schema and examples. Each report records these fields:

- Schema version, crap4ruby version, and Prism version.
- Revision supplied with `--revision`, as a full 40- or 64-character hexadecimal Git object ID. This is a caller assertion. The workflow example verifies it against its checkout.
- Canonical scan scope as sorted unique source roots relative to `--root`. Use `.` for the default scan. Record the coverage resultset path for provenance. Resultset filenames can differ between reports.
- Full method list. Each record includes a relative pathname, declaration line, namespace, method kind, name, cyclomatic complexity, coverage percentage or null, exact CRAP score or null, and coverage reason or null.

Store CRAP scores as rational strings with a positive denominator. The displayed percentage is informational. Keep names and kind separate so a literal instance method named `self.foo` differs from a singleton method named `foo`. Carry this distinction from Prism. Emit stable ordering and UTF-8 text. A path that cannot be represented losslessly in this schema produces an actionable export error. This leaves existing terminal handling of those paths intact.

Validate both reports before computing a verdict. Reject malformed data, unsupported schema versions, and mismatched crap4ruby versions, Prism versions, or scan scopes. A comparison can use reports for the same revision, for example to confirm that a repeated scan yields the same result. Validate each path and location, method kind, complexity, coverage bounds, rational form, and legal combinations of known scores and coverage reasons. Preserve repeated definitions. The report loader owns normalization and validation so the comparison can use typed records.

## Method matching

Pair a method with a unique match in both revisions on relative path, namespace, method kind, and name. Ignore declaration line changes when matching. Then pair remaining unambiguous matches on namespace, kind, and name across paths. Record the path move separately from the score change. A rename or owner change appears as a removal and an addition.

After pairing, report each remaining definition as an addition or removal when its identity has no remaining counterpart. If an identity has unmatched definitions on both sides and cannot be paired uniquely, report it as a group. Show the affected definitions and their locations. If the complete group has the same multiset of paths and measured values, treat it as an unchanged group for gating. A changed group with any current score or upper bound above the limit can hide a new method or regression and makes the gate uncertain. Use complexity, exact score, coverage, and coverage reason as the measurement fields. Never invent a per-method delta for ambiguous pairs.

## Verdict

Calculate one result for Markdown and the exit status. A method is above the limit only when its score is strictly higher. A measured increase is material only when its exact delta is strictly higher than `--min-increase`.

| Finding | Gate result |
| --- | --- |
| Matched measured method above the limit with a material increase | Measured violation |
| New measured method above the limit | Measured violation |
| Matched method that loses a known score, or new method with an unknown score | Uncertain if `CC^2 + CC` exceeds the limit |
| Matched method with an unknown baseline score | Show the unavailable comparison. It does not create a gate failure by itself. |
| Ambiguous group that changes | Uncertain if a current score or upper bound exceeds the limit |
| Existing measured score with no material increase, improvement, or removal | No violation |

The user chose the upper-bound rule for loss of measurable coverage. Applying that same bound to new methods and ambiguous groups is a proposed builder decision. An existing missing baseline measurement remains visible and does not require the team to clear every legacy unknown before enabling the check.

When enforcement is enabled, return exit 2 for any measured violation or exit 1 for uncertainty. A measured violation takes precedence. Return exit 0 when the gate passes. With enforcement disabled, a successfully rendered comparison exits 0. Invalid input or incomparable reports always exit 1 with a diagnostic and no partial Markdown verdict.

## Markdown and CI example

Lead with base and head revisions, active limits, and the verdict. Show actionable rows with before and after CRAP, complexity, coverage, and source locations. Explain uncertainty using the coverage reason and upper bound where applicable. Show any move beside its score result. Include counts for additions, removals, improvements, and unavailable comparisons. Put a short, bounded list of existing high scores in a collapsed section. Escape report fields for literal Markdown display. Exact column widths, labels, and the legacy list length are builder decisions.

Provide a sample GitHub Actions workflow. Run the project tests separately for the exact PR base and head commits. Use the same crap4ruby and Prism versions and source roots for both exports. Append the Markdown to `GITHUB_STEP_SUMMARY` even when the comparison returns a gate failure, and retain that exit status. Use a read-only `pull_request` workflow. An invalid report must still fail the comparison step. Existing repository CI stays on its absolute check for this change. [PR checkout behavior](https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows#how-the-merge-branch-affects-your-workflow), [Job summary interface](https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-commands#adding-a-job-summary).

Initial scope ends with the JSON export, comparison, policy, and job summary example. A sticky PR comment, SARIF, automatic test orchestration, and Git rename heuristics are follow-ups.

## Verification

Exercise both commands through the executable. Verify exact score round trips, relocated checkouts, different source line numbers, moves with regressions, ambiguous definitions, invalid input, and every gate outcome. Use a Git fixture with exact base and head revisions and real SimpleCov data to verify the workflow commands and job summary. Keep the existing regression suite and full `bundle exec rake` check green.
