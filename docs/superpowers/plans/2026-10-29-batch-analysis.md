# Automatic batch analysis implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Reduce complete CLI latency on large real projects with automatic bounded worker processes and exact serial behavior.

**Architecture:** Move file analysis and scoring into `Crap4Ruby::Batch`. It selects serial execution or a bounded group of forked workers, preserves file order, and owns all worker cleanup. The CLI retains discovery, coverage loading, output, thresholds, and snapshot writes.

**Tech Stack:** Ruby >= 3.3, Prism >= 1.0 and < 3, standard-library pipes, Marshal, Process, and Etc. No new dependency.

**Spec:** [Approved design](../specs/2026-10-29-batch-analysis-design.md), approved in chat on 2026-10-29.

## Global constraints

- Automatic execution uses at most four workers, never more than available processors.
- Start with a minimum of 64 files; retain or adjust it from real-subset crossover measurements.
- `--jobs 1` forces serial execution; explicit positive larger counts bypass the minimum-file threshold and cannot exceed the file count.
- Unsupported fork platforms and processes with other live Ruby threads use serial execution.
- Preserve ordered entries, exact scores, reports, diagnostics, exit codes, and snapshot behavior.
- Keep all report and snapshot writes in the parent; children use `exit!`.
- Close pipes and reap every owned child on success, failure, and cancellation.

## Review focus

- Large pipe payloads must not deadlock while other workers wait to write; test in Task 2 with bounded subprocess execution.
- Errors in multiple chunks must report the first serial-order error; test in Task 2 with distinct parse failures.
- An interrupted parent must not leave running children or zombies; test in Task 2 and independently inspect lifecycle behavior in Task 4.
- Fork resource exhaustion after partial startup must clean up and fall back without duplicate output; test in Task 2.
- Hosts with other threads and systems without fork must retain working serial analysis; test in Task 2 without requiring such a platform.

## Task 1: Extract ordered serial batch analysis

**Files:** Create `lib/crap4ruby/batch.rb` and `test/batch_test.rb`; modify `lib/crap4ruby.rb`, `lib/crap4ruby/cli.rb`, `sig/crap4ruby.rbs`, and `sig-development/tests.rbs`.

**Interfaces:** Consume `Analyzer#call(source, path:)`, `Score.call(method, coverage)`, and `Coverage#fraction`. Produce `Batch.call(files, coverage, jobs: nil) -> Array[Entry]`. Initially preserve serial execution; the following task adds the selected execution policy.

- [x] Write `test_serial_batch_preserves_order_and_coverage`: analyze two temporary files in reversed filename order, compare complete entries to the current Analyzer/Score loop, and check exact partial-coverage Rational scores. Add empty input and parse/filesystem error assertions.
- [x] Run `bundle exec ruby -Itest test/batch_test.rb`; require failure because Batch is undefined.
- [x] Implement the serial `Batch.call`, wire its require and RBS signatures, and delegate the existing CLI analysis loop to it without changing CLI options.
- [x] Run `bundle exec ruby -Itest test/batch_test.rb`, `bundle exec rake test lint types crap docs:check`; require exact entry equality and all gates passing.
- [x] Commit as `refactor(batch): extract ordered file analysis`.

## Task 2: Add bounded workers and lifecycle guarantees

**Files:** Modify `lib/crap4ruby/batch.rb`, `test/batch_test.rb`, and `sig/crap4ruby.rbs`; add `test/batch_process_test.rb` for bounded subprocess checks.

**Interfaces:** Extend Task 1's `Batch.call(files, coverage, jobs: nil)`. Private helpers own worker-count selection, serial analysis, fork startup, ordered result collection, child payload generation, and cleanup. No caller receives worker handles.

- [x] Add failing tests for serial/parallel complete-entry equality, actual child execution, deterministic ordering, automatic cap and threshold, explicit worker counts, unsupported-fork and multithreaded fallbacks. Reject nonpositive direct `jobs` arguments with `ArgumentError` before starting workers.
- [x] Add bounded subprocess tests for payloads larger than pipe buffers, two chunks failing in different orders, filesystem errors, malformed/missing payloads, nonzero exits, partial-start resource failure, and interrupt cleanup. Assert no pending child remains using owned PID checks and `waitpid` behavior; do not inspect unrelated processes.
- [x] Run both batch test files and confirm they fail on missing parallel behavior, not fixture errors.
- [x] Implement contiguous nonempty chunks, private pipes, typed Marshal payloads, and ordered parent collection. Preserve exception classes/messages for expected analysis errors. Handle startup `EAGAIN`/`ENOMEM` by cleaning up then falling back to serial. Convert protocol and worker-exit failures to `Crap4Ruby::Error`. Ensure cleanup closes pipes and terminates/reaps pending children without waiting for unfinished work.
- [x] Run both batch test files repeatedly with different test seeds, then `bundle exec rake test lint types crap docs:check`. Require bounded completion, no orphaned children, full type coverage, and method CRAP <= 10.
- [x] Commit as `feat(batch): analyze large inputs with bounded workers`.

## Task 3: Expose the serial override and preserve CLI failure behavior

**Files:** Modify `lib/crap4ruby/cli.rb`, `sig/crap4ruby.rbs`, `test/cli_test.rb`, `test/integration_test.rb`, `README.md`, and `CHANGELOG.md`.

**Interfaces:** Parse `--jobs N` as a positive Integer and pass `jobs:` to `Batch.call`. Absence means automatic selection. Help/version and unrelated coverage options retain their behavior.

- [x] Add failing CLI tests for help text, `--jobs 1`, `--jobs 2`, invalid zero/negative/noninteger arguments, and exact parallel-versus-serial table/snapshot/status equality.
- [x] Add subprocess integration cases where worker analysis fails or exits abnormally; assert status 1, one useful diagnostic, no partial report, and preservation of an existing snapshot. Check threshold statuses 0, 1, and 2 against serial execution.
- [x] Run focused CLI and integration tests and confirm the new option is the cause of failure.
- [x] Implement option parsing, signature changes, delegation, and concise documentation of automatic eligibility, resource cost, fallbacks, and the serial override.
- [x] Run `bundle exec rake`; require lint, Steep, 100% type coverage, tests, CRAP, YARD checks, and both dependency audits passing. Commit as `feat(cli): expose batch worker control`.

## Task 4: Establish crossover, real-project gains, and independent evidence

**Files:** Modify `PERFORMANCE.md` and `script/benchmark.rb` only if needed for explicit serial comparisons; add raw evidence under `benchmark/results/`. Adjust the automatic minimum in `batch.rb` and its policy test only when crossover results justify it.

**Interfaces:** Use the committed benchmark runner's clean child boot, alternating order, input/library hash guards, and byte-for-byte report check. Compare current default execution against both `6a1701b` and `19942c2`; independently compare current `--jobs 1` with its default.

- [x] Measure real Forem and Les file subsets around 16, 32, 64, and 128 files, plus the full selections. Include fork startup and result transfer. Use seven alternating measured samples after warmup and retain all input and output hashes. Set the automatic crossover from those results.
- [x] Run complete CLI comparisons serially on Les with and without coverage, Forem, Steep, and YARD. Require clear latency gains on eligible large inputs and no meaningful regression for serial/small input paths. Do not compare medians from separate campaigns as an isolated improvement.
- [x] Capture total CPU time and separately sampled summed RSS, with shared-page and polling limitations. Record all raw samples and distinguish phase, complete CLI, and memory-probe data.
- [x] Request independent QA and whole-branch review focused on parity, descriptor inheritance, deadlocks, error ordering, cancellation, fallback, supported Ruby versions, and the exact documented measurements. Fix verified findings and rerun affected checks.
- [x] Run `bundle exec rake`, validate saved evidence against originals, and commit as `test(performance): verify automatic batch analysis`. Remove throwaway scripts, preserve evidence, and confirm a clean worktree.
