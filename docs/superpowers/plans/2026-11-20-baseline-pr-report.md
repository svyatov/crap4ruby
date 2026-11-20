# Baseline comparison for pull requests implementation plan

> For agentic workers, use `superpowers:executing-plans` or `superpowers:subagent-driven-development`.

**Goal.** Export complete analysis reports and compare two revisions in CI.

**Architecture.** Share one versioned JSON contract between the exporter and importer. Keep matching and policy separate from Markdown so the gate and report use the same result.

**Tech stack.** Ruby 3.3+, Prism, SimpleCov, JSON, Minitest, Steep, and GitHub Actions.

**Spec.** [Baseline comparison](../specs/2026-11-20-baseline-pr-report-design.md).

## Constraints

Use F1 commit `80d4d19` as the base. Preserve scoring, the EDN contract, and the normal CLI. Keep comparison read-only.

## Review focus

- Distinguish literal `self.foo` instance methods from singleton methods.
- Compare exact rational scores at the policy limits.
- Check a regression even when its method moved.
- Keep uncertainty visible when coverage or a method match is unavailable.
- Write the Markdown job summary before propagating a gate exit.

## Task 1. Export and validate reports

- [x] Test the JSON and snapshot behavior through the CLI, including literal names, exact scores, empty scans, and invalid scopes.
- [x] Run the targeted test before implementation and confirm it fails on the missing export flag.
- [x] Carry Ruby method kind from the analyzer. Add a report codec with typed method records, schema validation, and stable JSON.
- [x] Wire export flags into the existing CLI. Prepare JSON before the EDN write so invalid paths preserve the previous snapshot.
- [x] Verify the targeted tests and publish the versioned schema.

## Task 2. Compare and render

- [x] Test matched scores, moves, duplicate groups, additions, removals, and the approved uncertainty cases.
- [x] Run the targeted tests before implementation and confirm they fail on missing comparison behavior.
- [x] Match unique path-scoped identities, then unique Ruby identities. Apply the policy to one result used by Markdown and the gate.
- [x] Add the read-only compare flags and render diagnostics separately from Markdown.
- [x] Test report-only exit 0, measured exit 2, uncertainty exit 1, malformed reports, incompatible settings, and escaped Markdown.

## Task 3. Verify the workflow

- [x] Document the commands and provide a GitHub Actions example using the exact base and head SHAs.
- [x] Run the workflow commands against two local Git revisions with SimpleCov coverage. Inspect the resulting Markdown and verify the gate exit is preserved.
- [x] Run `bundle exec rake`, inspect the generated project snapshot, and commit the verified feature and approved design.
