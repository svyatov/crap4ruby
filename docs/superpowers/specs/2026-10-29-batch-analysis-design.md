# Automatic batch analysis

## Intent

Reduce CLI latency on large Ruby projects without changing analysis, coverage, scores, report bytes, exit codes, or snapshot behavior. The user selected automatic, bounded workers for large projects over an explicit opt-in worker option. Existing serial optimizations remain in place.

## Evidence and resource cost

The fork prototype analyzed and scored the actual selected files from Forem and Les. Seven measured rounds followed an excluded warmup round. Four workers reduced analysis-and-scoring latency from 0.4104 s to 0.1504 s on Forem and from 0.1220 s to 0.0566 s on coverage-enabled Les. Total parent-plus-child CPU time increased by 11% and 26%, respectively. Returned entries and input hashes matched across worker counts. These are phase measurements, not complete CLI measurements.

A separate seven-trial Forem probe sampled parent and worker RSS. Median peak summed RSS was 69,206,016 bytes with one process, 153,255,936 bytes with two workers, and 243,908,608 bytes with four workers. Shared pages are counted once per process, so these are sampled sums, not aggregate physical memory. The monitor can perturb timing; its elapsed times must not be used to claim a speed gain.

The same probe on coverage-enabled Les measured 46,694,400, 105,955,328, and 123,551,744 bytes with one process, two workers, and four workers. [Raw resource samples](../../../benchmark/results/2026-10-29-batch-resources.jsonl) retain every trial. Existing [phase timing samples](../../../benchmark/results/2026-10-29-report-score.jsonl) come from separate runs without the RSS monitor.

## Approaches

1. Automatic bounded workers, selected by the user: accelerate eligible large CLI runs by default, with a serial override and conservative eligibility checks. This increases process and memory use.
2. Explicit opt-in workers: preserve serial resource use by default, but require each caller to discover and configure the feature. The user did not select this approach.
3. Serial execution only: preserve the simplest runtime model but leave the measured batch speed gain unavailable. Threads do not provide parallel Ruby traversal under MRI's global VM lock. A new process-pool dependency is unnecessary for this bounded operation.

## Execution contract

Add a `Crap4Ruby::Batch` module that owns file analysis and scoring. Its `call(files, coverage, jobs: nil)` method returns the same ordered `Array<Entry>` as the existing CLI loop. It reads source files without executing their Ruby code. The CLI delegates to it and keeps discovery, coverage loading, sorting, threshold decisions, table output, and snapshot writes in the parent process.

With `jobs: nil`, use at most four workers, never more than the available processors. Start with a minimum of 64 files for automatic execution. Measure the crossover on real project subsets before retaining that threshold; adjust it from those measurements. Empty selections, one effective worker, unsupported fork platforms, and processes with other live Ruby threads use the serial path. This avoids introducing fork into an existing multithreaded host. Direct `Analyzer` calls remain serial and retain their current interface.

Add `--jobs N` with a positive integer argument. `--jobs 1` forces serial execution. Explicit larger counts bypass the automatic minimum-file threshold, but the worker count never exceeds the number of files. Unsupported fork platforms and multithreaded hosts still use serial execution. Help and README text describe these fallbacks. Do not add an environment variable or persistent configuration file.

The automatic limit, CPU selection, and crossover policy are implementation choices proposed here, not preferences previously supplied by the user.

## Worker protocol and ordering

Partition files into contiguous, nonempty chunks in discovery order. Fork only after discovery and coverage loading. Each worker receives its chunk and the inherited coverage reader, creates its own analyzer, and returns scored entries through a private pipe. Coverage data remains read-only. Parent code concatenates chunk results in original order, so ties and direct batch callers retain the serial order.

Use Ruby Marshal only for data from these child processes. No serialized payload from source files or an external service is accepted. Workers send either entries or the captured analysis exception. Expected parse and filesystem errors retain their exception class and diagnostic message. Read all workers' results and select the first analysis error in original chunk order, preserving serial first-error behavior.

Children do not write reports, snapshots, or normal diagnostics. They close their pipe and use `exit!`, so inherited exit hooks do not run. The parent waits for every child. There is no persistent pool, thread scheduler, or cross-run cache.

## Failure and cancellation

If fork is unavailable or a worker cannot be started because of a resource-limit error, close pipes, terminate and reap already-started workers, then run the read-only analysis serially. Do not retry analysis failures in a different mode.

A worker that exits without a complete payload, returns malformed data, or exits unsuccessfully produces a concise `Crap4Ruby::Error`. Do not publish partial entries or replace the snapshot. An ensure block closes every parent pipe and terminates and reaps all remaining owned children on errors, interrupts, or early exits. Cancellation must not wait for unfinished analysis. Cleanup targets only PIDs created by this call.

## Verification

1. Add behavior tests before implementation for ordered serial/parallel equality, coverage fractions, empty and small selections, explicit worker counts, unsupported fork and multithreaded fallbacks, and argument validation.
2. Exercise real child processes for parse and filesystem errors, chunk-order first errors, large payloads, missing or corrupt payloads, abnormal worker exits, partial-start failure, and cancellation. Check that children are reaped and old snapshots remain intact. Use bounded subprocess tests so a protocol deadlock fails instead of hanging the suite.
3. Run fixture and real-project differential checks on supported Ruby versions. Preserve entry fields, order, table and EDN bytes, diagnostics, and exit statuses. Fork-specific checks skip with an explicit reason where unsupported; serial fallback remains tested.
4. Compare complete CLI runs against `6a1701b` and the original `19942c2` baseline on the same four real projects, with seven alternating measured samples after warmup, stable input hashes, and identical reports. Also check real subsets around the automatic crossover and `--jobs 1`.
5. Record raw samples, total CPU time, and separately sampled summed RSS with its limitations. Require a clear complete-CLI latency reduction for eligible large projects and no meaningful regression for serial or small inputs. Run the existing lint, type coverage, tests, CRAP, documentation, and dependency audit gates.

## Scope and remaining builder decisions

No new gem, native extension, Ractor interface, daemon, cache, or change to the CRAP formula is required. File partitioning can be changed only if real-project measurements justify it and output order remains exact. The builder chooses small private helpers, pipe cleanup details, and fixture construction. Independent review must examine deadlocks, descriptor inheritance, worker lifecycle, and first-error ordering before the default is enabled.
