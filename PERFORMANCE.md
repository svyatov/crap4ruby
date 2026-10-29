# Performance

The benchmark compares complete CLI runs on local project checkouts. It checks report equality and rejects changed inputs.

## Measured results (2026-10-29)

Baseline: `19942c2` (0.2.1). Candidate: `6a1701b`. Runtime: Ruby 4.0.9, Prism 1.9.0, arm64 macOS.

Each variant has seven measured subprocess runs after one excluded warmup. Variant order alternates, and runs execute serially with warm filesystem caches.

| Project | Mode | Ruby files | Baseline median | Candidate median | Time reduction |
| --- | --- | ---: | ---: | ---: | ---: |
| Les | Complexity only | 196 | 0.2501 s | 0.1839 s | 26.5% |
| Les | SimpleCov coverage | 196 | 0.2895 s | 0.2394 s | 17.3% |
| Forem | Complexity only | 1,307 | 0.9923 s | 0.6276 s | 36.8% |
| Steep | Complexity only | 146 | 0.5512 s | 0.3287 s | 40.4% |
| YARD | Complexity only | 207 | 0.3753 s | 0.2609 s | 30.5% |

[Raw samples and input/output hashes](benchmark/results/2026-10-29-report-score.jsonl) retain every measured duration. Each line is a JSON object; the first contains campaign metadata. The final four objects contain formatting, scoring, and batch experiments described below.

The earlier campaigns measured [candidate `80484fd`](benchmark/results/2026-10-29.jsonl) and [candidate `2f35bdd`](benchmark/results/2026-10-29-follow-up.jsonl) against the same baseline. Project input and report hashes match across campaigns. Timing differences between campaigns do not isolate individual changes.

Timing includes Ruby startup, Prism activation, discovery, source reads, analysis, coverage loading, sorting, formatting, output capture, and process completion. Both variants start without inherited Bundler setup and activate the same Prism version. Runs use `--no-save`, so timing excludes snapshot serialization and writes. Test-suite execution is excluded.

Every measured report matches its baseline byte for byte. Separate differential checks preserve all fields and traversal order across 10,568 method definitions in these four projects. Independent fixture checks cover nested definitions, heredocs, encoding, assignment syntax, errors, and coverage on Ruby 3.3.11 and 4.0.9 with Prism 1.9.0. Prism 1.0 and 2.x were not executed.

These results describe local checkouts and warm filesystem caches. They do not establish cold-disk latency, peak memory, or performance on other machines.

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

### Batch prototype

A throwaway fork-based prototype tested analysis and scoring across files. It does not change the library. It excludes CLI startup, discovery, sorting, formatting, and saving. Seven measured rounds followed one excluded warmup round; worker order rotated. Selected file contents and all returned entries matched across worker counts.

| Project and mode | Worker processes | Median elapsed time | Median total CPU time |
| --- | ---: | ---: | ---: |
| Forem, complexity only | 1 | 0.4104 s | 0.4059 s |
| Forem, complexity only | 2 | 0.2656 s | 0.4365 s |
| Forem, complexity only | 4 | 0.1504 s | 0.4507 s |
| Les, coverage | 1 | 0.1220 s | 0.1211 s |
| Les, coverage | 2 | 0.0776 s | 0.1377 s |
| Les, coverage | 4 | 0.0566 s | 0.1532 s |

Four workers reduced phase latency by 63% on Forem and 54% on Les, while increasing total CPU time by 11% and 26%. Total CPU includes parent and child processes. Aggregate memory, portability, worker cancellation, and failure behavior still need evaluation before adding this execution model. These measurements do not establish a performance maximum.
