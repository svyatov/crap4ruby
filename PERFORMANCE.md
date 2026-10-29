# Performance

The benchmark compares complete CLI runs on local project checkouts. It checks report equality and rejects changed inputs.

## Measured results (2026-10-29)

Baseline: `19942c2` (0.2.1). CLI candidate: `2f23c80`. Final EDN allocation follow-up: `3dd909d`, measured separately below. Runtime: Ruby 4.0.9, Prism 1.9.0, arm64 macOS.

Each variant has seven measured subprocess runs after one excluded warmup. Variant order alternates, and runs execute serially with warm filesystem caches.

| Project | Mode | Ruby files | Baseline median | Candidate median | Time reduction |
| --- | --- | ---: | ---: | ---: | ---: |
| Les | Complexity only | 196 | 0.2530 s | 0.1485 s | 41.3% |
| Les | SimpleCov coverage | 196 | 0.2840 s | 0.1788 s | 37.1% |
| Forem | Complexity only | 1,307 | 0.9631 s | 0.3761 s | 60.9% |
| Steep | Complexity only | 146 | 0.5330 s | 0.2185 s | 59.0% |
| YARD | Complexity only | 207 | 0.3699 s | 0.1768 s | 52.2% |

[Raw samples and input/output hashes](benchmark/results/2026-10-29-batch.jsonl) retain every measured duration. Each line is a JSON object. Campaign records distinguish the original baseline, the optimized serial baseline, current-code worker settings, and small inputs. Grouped samples factor identical metadata without dropping values. Phase, resource, and independent QA records are separate.

The earlier campaigns measured [candidate `80484fd`](benchmark/results/2026-10-29.jsonl), [candidate `2f35bdd`](benchmark/results/2026-10-29-follow-up.jsonl), and [candidate `6a1701b`](benchmark/results/2026-10-29-report-score.jsonl) against the same baseline. Project input and report hashes match across campaigns. Timing differences between campaigns do not isolate individual changes.

Timing includes Ruby startup, Prism activation, discovery, source reads, analysis, coverage loading, sorting, formatting, output capture, and process completion. Both variants start without inherited Bundler setup and activate the same Prism version. Runs use `--no-save`, so timing excludes snapshot serialization and writes. Test-suite execution is excluded.

Every measured report matches its baseline byte for byte. Separate differential checks preserve all fields and traversal order across 10,568 method definitions in these four projects. Independent fixture checks cover nested definitions, heredocs, encoding, assignment syntax, errors, and coverage on Ruby 3.3.11 and 4.0.9. The batch implementation also passed 75 independent CLI runs and 21 controlled lifecycle probes on Ruby 3.3.11, 3.4.9, and 4.0.9. All used Prism 1.9.0. Prism 1.0 and 2.x were not executed.

These results describe local checkouts and warm filesystem caches. They do not establish cold-disk latency, unique physical memory use, or performance on other machines. Separately sampled summed RSS is reported below.

## Repeat the comparison

1. Create a scratch directory with `mktemp -d`. Replace `BASELINE_DIR` below with its printed path.
2. Export the baseline library:

   ```sh
   git archive --output=BASELINE_DIR/baseline.tar 19942c2 lib
   ```

3. Extract the archive:

   ```sh
   tar -xf BASELINE_DIR/baseline.tar -C BASELINE_DIR
   ```

4. Compare against a project checkout:

   ```sh
   bundle exec ruby script/benchmark.rb BASELINE_DIR/lib /path/to/project
   ```

The command prints JSON to stdout and median/range summaries to stderr. Pass multiple project paths to measure them serially. Set `SAMPLES` to an odd integer of at least three to change the sample count.

For a comparison of current-code serial execution against its automatic default, use `BASELINE_JOBS=1` and pass `lib` as the baseline directory. `CANDIDATE_JOBS` can override the candidate worker count. Both optional settings are recorded in the output; use them only with library versions that support `--jobs`.

The runner selects existing `app/` and `lib/` directories. It measures complexity-only mode and adds coverage-enabled mode when `coverage/.resultset.json` exists. It hashes selected paths and contents before and after each subprocess. Coverage-enabled runs also hash the coverage report. Library hashes must remain unchanged throughout the campaign.

## Optimization evidence

The analyzer shares one ordered result array across discovery, uses symbol dispatch for decision types, and resolves coverage endpoints by byte offset. Complexity-only CLI runs omit coverage line collection. Default library calls retain body lines.

Analysis-only comparisons against the baseline preserved complete method records and reports. They reduced median analysis time by 18% to 25% before omitting coverage collection. The omitted walk then reduced complete complexity-only CLI latency by another 16% to 23% against that intermediate implementation.

Preliminary CLI timings inherited Bundler's candidate version preload and were replaced by the clean-boot measurements above. The newer Prism child iterator was excluded because the minimum supported Prism version lacks it.

### Follow-up experiments

Seven trials per variant alternated execution order. Each trial started a separate Ruby process and ran one excluded warmup batch. Phase timing excludes library loading and result hashing. Allocation counts use `GC.stat(:total_allocated_objects)` deltas.

| Experiment | Input and batch | Baseline median | Candidate median | Baseline allocated objects | Candidate allocated objects |
| --- | --- | ---: | ---: | ---: | ---: |
| Iteration membership hash | Forem, one complexity-only analysis | 0.4041 s | 0.3911 s | 944,945 | 945,015 |
| Direct definition-boundary checks | Forem, one analysis with body lines | 0.5592 s | 0.5284 s | 1,374,461 | 1,186,622 |
| Copy initial coverage counts | Les, 50 report loads | 0.3416 s | 0.2707 s | 1,434,813 | 87,463 |
| Skip repeated file-type checks | Forem, 20 discovery calls | 1.8376 s | 1.6761 s | 1,061,220 | 993,820 |

Each phase isolates one change against its preceding implementation. Analysis includes source reads and parsing. Coverage loading includes JSON parsing, validation, and normalization. Its input is the real Les report with 209 files and 13,399 line entries. The loader experiment screened an equivalent conditional form before the committed guard clause.

Complete method records, merged coverage data, and selected file paths match within every phase. Independent checks also matched 382 Analyzer fixtures, 176 coverage cases, and 40 discovery scenarios on Ruby 3.3.11 and 4.0.9. Coverage checks include caller-array mutation, merged suites, unequal arrays, and symlink aliases.

Moving the iteration block check before membership lookup showed no clear gain and was reverted.

### Formatting and scoring

The table formatter now uses one format template per report. Scoring combines integer terms before constructing the exact Rational result. Both changes preserve output and reduce allocated objects.

| Experiment | Input and batch | Baseline median | Candidate median | Baseline allocated objects | Candidate allocated objects |
| --- | --- | ---: | ---: | ---: | ---: |
| Table format template | Forem, 20 tables of 5,765 entries | 0.1991 s | 0.1206 s | 1,384,240 | 461,740 |
| Integer score terms | Les, 20 scoring passes over 1,045 methods | 0.3267 s | 0.3192 s | 397,060 | 250,020 |

Each experiment has seven alternating trials per variant, with one excluded warmup batch per process. The table experiment compares `562581a` with the formatter in `c0f10f6`. The scoring experiment compares `c0f10f6` with `6a1701b`. Allocation counts cover the measured batch only.

The formatter reduced phase time by 39% and allocated objects by 67%. Scoring reduced allocated objects by 37%. Its elapsed time changed by 2.3%, and CPU time changed from 0.3256 s to 0.3175 s. These small timing changes do not establish a reliable speed gain. Median process peak RSS was 47,398,912 versus 47,431,680 bytes. Median GC count was 17 for both variants; candidate batches triggered 16 to 17 collections. Median GC time was 12 versus 10 ms. Fewer allocations are a retained improvement even without a demonstrated reduction in peak memory or median collection count.

Independent differential checks matched 146 formatter cases and 74 scoring cases on Ruby 3.3.11 and 4.0.9. These include encoding and control characters, exact Rational values, partial coverage, and large integers.

#### EDN allocation follow-up

Commit `3dd909d` trims trailing zeros in the newly formatted number string in place. This avoids copying that string. Each variant runs 100 EDN formatting passes after 100 excluded warmup passes, in seven fresh subprocesses with alternating order. Timing excludes library loading, analysis, sorting, and snapshot writes. The baseline is `af2f770`.

| Input | Baseline median | Candidate median | Baseline allocated objects | Candidate allocated objects |
| --- | ---: | ---: | ---: | ---: |
| Les, 1,045 methods with coverage | 0.1696 s | 0.1699 s | 1,701,309 | 1,517,509 |
| Forem, 5,765 methods without coverage | 0.3711 s | 0.3687 s | 2,894,109 | 2,894,109 |

Les report allocations decreased by 10.8%. Forem has no numeric coverage or scores to trim, so its allocation count is unchanged. Timing ranges overlap for both inputs; these results establish no elapsed-time improvement. All EDN hashes match, and all selected source and coverage hashes remain unchanged. [Raw samples and QA evidence](benchmark/results/2026-10-29-edn.jsonl) retain every duration and allocation count. Differential checks preserve 4,012 numeric cases on each of Ruby 3.3.11, 3.4.9, and 4.0.9. Additional EDN checks cover escaping, empty reports, exact Rational values, negative zero, and nonfinite floats on Ruby 3.3.11 and 3.4.9.

### Automatic batch analysis

Selections of at least 64 files use up to four worker processes, bounded by available processors. Smaller selections, unsupported fork platforms, and hosts with other live Ruby threads remain serial. `--jobs 1` forces serial execution. Result order and all report writes remain controlled by the parent.

The following campaign compares the same `2f23c80` library with `--jobs 1` against its automatic default. It isolates worker selection without changing the loaded library. Each mode has seven alternating measured subprocess runs after one excluded warmup.

| Project | Mode | Serial median | Automatic median | Time reduction |
| --- | --- | ---: | ---: | ---: |
| Les | Complexity only | 0.1960 s | 0.1579 s | 19.4% |
| Les | SimpleCov coverage | 0.2438 s | 0.1800 s | 26.1% |
| Forem | Complexity only | 0.6207 s | 0.3822 s | 38.4% |
| Steep | Complexity only | 0.3215 s | 0.2160 s | 32.8% |
| YARD | Complexity only | 0.2507 s | 0.1732 s | 30.9% |

A separate paired campaign against the earlier optimized serial implementation, `6a1701b`, measured reductions of 19.6% to 40.0%. All reports matched. The raw data keeps this comparison separate from the original-baseline and worker-override campaigns.

Real-project subsets support the 64-file automatic threshold. The phase experiment includes source reads, parsing, scoring, fork startup, cancellation-thread startup, and result transfer. It excludes discovery, coverage loading, sorting, formatting, and process startup. Each trial has one excluded warmup batch; worker order rotates across seven fresh subprocess trials.

| Project | Selected files | Serial phase median | Four-worker phase median |
| --- | ---: | ---: | ---: |
| Forem | 16 | 0.0063 s | 0.0087 s |
| Forem | 32 | 0.0124 s | 0.0114 s |
| Forem | 64 | 0.0272 s | 0.0198 s |
| Forem | 128 | 0.0439 s | 0.0241 s |
| Les, coverage | 16 | 0.0068 s | 0.0116 s |
| Les, coverage | 32 | 0.0174 s | 0.0157 s |
| Les, coverage | 64 | 0.0301 s | 0.0197 s |
| Les, coverage | 128 | 0.0648 s | 0.0307 s |

Four workers lose at 16 files, show smaller gains at 32, and reduce phase time by 27% to 35% at 64. On the full selections, automatic analysis-and-scoring time was 0.1599 s versus 0.4082 s for Forem, and 0.0575 s versus 0.1186 s for Les. Median total parent-plus-child CPU time increased from 0.4073 s to 0.4615 s on Forem, and from 0.1180 s to 0.1608 s on Les: increases of 13.3% and 36.2%.

Seven alternating memory probes per configuration sampled the sum of CLI parent and worker RSS every 10 ms. This includes startup and reporting; fork telemetry and polling perturb timing, so these probes support no latency claim. Shared pages are counted once per process, and sampling can miss short peaks. These are not measurements of unique physical memory.

| Project | Serial median sampled peak sum RSS | Automatic median sampled peak sum RSS |
| --- | ---: | ---: |
| Forem | 73,678,848 bytes | 194,854,912 bytes |
| Les, coverage | 47,005,696 bytes | 112,443,392 bytes |

Independent QA compared serial baseline `6a1701b` with automatic mode and `--jobs 1/2/4` through actual CLI subprocesses on all four projects. It preserved stdout, stderr, exit statuses, source and coverage inputs, and existing snapshots across three Ruby versions. Controlled probes exercised ordering, exact Rational scores, Unicode, payloads larger than a pipe buffer, malformed results, abnormal exits, first-error ordering, multithreaded fallback, cancellation, and custom SIGCHLD reapers. All probes finished without remaining children. Cleanup made no PID signals and did not replace host signal handlers. The main suite additionally covers unavailable fork, partial startup failure, and SIGINT cancellation.

Review found a stale-PID signaling race when a host reaped worker statuses. The repaired implementation cancels through private pipes and uses a child monitor thread, then validates complete result payloads even if the host has consumed the exit status. The two reproducing regression tests and the full 86-test suite pass. The measurements above include this repair.

A separate [process-group SIGINT probe](benchmark/results/2026-10-29-batch-sigint.json) delivered SIGINT after all four workers started. The CLI terminated on signal 2, preserved its existing snapshot, emitted no report, and left no processes in its group.

Small-input CLI comparisons against `6a1701b` remained serial. Medians for 16 and 32 files ranged from effectively unchanged to 4.0% slower, with overlapping timing ranges. The largest median difference was 5.1 ms. A follow-up rejected deferred loading of `Etc`: `Tempfile` loads it transitively, and repeated load and CLI measurements showed no clear benefit. [The rejected experiment](benchmark/results/2026-10-29-startup-screen.json) retains all samples and its prototype description. EDN serialization was screened separately above. These measurements do not establish a performance maximum.

### Batch screening prototype

An earlier throwaway fork-based prototype screened analysis and scoring across files before the production worker implementation. These historical phase measurements exclude CLI startup, discovery, sorting, formatting, and saving. Seven measured rounds followed one excluded warmup round; worker order rotated. Selected file contents and all returned entries matched across worker counts. The prototype samples are retained in the earlier report-and-score campaign.

| Project and mode | Worker processes | Median elapsed time | Median total CPU time |
| --- | ---: | ---: | ---: |
| Forem, complexity only | 1 | 0.4104 s | 0.4059 s |
| Forem, complexity only | 2 | 0.2656 s | 0.4365 s |
| Forem, complexity only | 4 | 0.1504 s | 0.4507 s |
| Les, coverage | 1 | 0.1220 s | 0.1211 s |
| Les, coverage | 2 | 0.0776 s | 0.1377 s |
| Les, coverage | 4 | 0.0566 s | 0.1532 s |

Four workers reduced prototype phase latency by 63% on Forem and 54% on Les, while increasing total CPU time by 11% and 26%. Total CPU includes parent and child processes. The production implementation and its resource costs are measured separately above.
