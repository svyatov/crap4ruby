# Performance

The benchmark compares complete CLI runs on local project checkouts. It checks report equality and rejects changed inputs.

## Measured results (2026-10-29)

Baseline: `19942c2` (0.2.1). Candidate: `80484fd`. Runtime: Ruby 4.0.9, Prism 1.9.0, arm64 macOS.

Each variant has seven measured subprocess runs after one excluded warmup. Variant order alternates, and runs execute serially with warm filesystem caches.

| Project | Mode | Ruby files | Baseline median | Candidate median | Time reduction |
| --- | --- | ---: | ---: | ---: | ---: |
| Les | Complexity only | 196 | 0.2275 s | 0.1716 s | 24.5% |
| Les | SimpleCov coverage | 196 | 0.2653 s | 0.2372 s | 10.6% |
| Forem | Complexity only | 1,307 | 0.9097 s | 0.6313 s | 30.6% |
| Steep | Complexity only | 146 | 0.5040 s | 0.3201 s | 36.5% |
| YARD | Complexity only | 207 | 0.3451 s | 0.2342 s | 32.1% |

[Raw samples and input/output hashes](benchmark/results/2026-10-29.jsonl) retain every measured duration. Each line is a JSON object; the first contains campaign metadata.

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

Remaining profiling candidates include iteration membership lookups, definition-boundary allocations, discovery, and coverage merging. The measurements above do not establish a performance maximum.
