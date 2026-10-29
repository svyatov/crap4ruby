# Performance

The benchmark compares complete CLI runs on local project checkouts. It checks report equality and rejects changed inputs.

## Measured results (2026-10-29)

Baseline: `19942c2` (0.2.1). Candidate: `2f35bdd`. Runtime: Ruby 4.0.9, Prism 1.9.0, arm64 macOS.

Each variant has seven measured subprocess runs after one excluded warmup. Variant order alternates, and runs execute serially with warm filesystem caches.

| Project | Mode | Ruby files | Baseline median | Candidate median | Time reduction |
| --- | --- | ---: | ---: | ---: | ---: |
| Les | Complexity only | 196 | 0.2307 s | 0.1698 s | 26.4% |
| Les | SimpleCov coverage | 196 | 0.2838 s | 0.2361 s | 16.8% |
| Forem | Complexity only | 1,307 | 0.9554 s | 0.6072 s | 36.5% |
| Steep | Complexity only | 146 | 0.5001 s | 0.3073 s | 38.5% |
| YARD | Complexity only | 207 | 0.3403 s | 0.2354 s | 30.8% |

[Raw samples and input/output hashes](benchmark/results/2026-10-29-follow-up.jsonl) retain every measured duration. Each line is a JSON object; the first contains campaign metadata. The final four objects contain phase experiments described below.

The [earlier campaign](benchmark/results/2026-10-29.jsonl) measured candidate `80484fd` against the same baseline. Project input and report hashes match across campaigns. Timing differences between campaigns do not isolate the follow-up changes.

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

Moving the iteration block check before membership lookup showed no clear gain and was reverted. Remaining profiling candidates include scoring, report formatting, and batch analysis. These measurements do not establish a performance maximum.
