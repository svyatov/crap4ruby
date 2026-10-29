# crap4ruby

crap4ruby identifies complex, under-tested Ruby methods using the Change Risk Anti-Pattern (CRAP) metric.

- Analyzes Ruby 3.3+ methods without loading application code.
- Ranks methods using complexity and test coverage, rather than complexity alone.
- Reads existing SimpleCov reports and merges coverage across test suites.
- Checks one file, directories, or only files changed in Git.

## Install

Ruby 3.3 or newer is required.

```sh
gem install crap4ruby
```

In an empty directory, create a sample and analyze it:

```sh
printf 'def eligible?(age) = age >= 18\n' > sample.rb
crap4ruby --no-coverage sample.rb
# Reports eligible? with CC 1; coverage and CRAP are N/A.
# Writes .metrics/crap.edn.
```

In an existing project, select the source you want to measure:

```sh
crap4ruby --no-coverage
crap4ruby
crap4ruby --threshold 30
crap4ruby app/models/user.rb
crap4ruby app/models lib/billing
```

The first command reports complexity alone. The other commands require `coverage/.resultset.json` from your project's test run.

To use Bundler, add `gem "crap4ruby", require: false` to your project's `Gemfile` and run `bundle install`.
Run the tool with `bundle exec crap4ruby`.

## Install from source

Run these commands from this checkout with Ruby 3.3 or newer:

```sh
bundle install
gem build crap4ruby.gemspec
gem install ./crap4ruby-0.2.1.gem
```

To use Bundler in the measured project, add this checkout to that project's `Gemfile`:

```ruby
gem "crap4ruby", path: "/absolute/path/to/crap4ruby", require: false
```

Then run `bundle install` and `bundle exec crap4ruby` in that project.

## Set up coverage

[SimpleCov](https://github.com/simplecov-ruby/simplecov) must start before the application loads. Add it to the measured project's `Gemfile`:

```ruby
gem "simplecov", require: false, group: :test
```

Place this at the top of `test/test_helper.rb` or `spec/spec_helper.rb`, before requiring application code:

```ruby
require "simplecov"
SimpleCov.start
```

Run your tests, then run `crap4ruby`. RSpec and Minitest work through the same SimpleCov report format.

You can also supply an explicit command:

```sh
crap4ruby --coverage-command 'bundle exec rspec'
crap4ruby --coverage custom/.resultset.json
```

The command runs through `sh` at the project root with the caller's environment. Its output goes to stderr.
It must exit successfully and create or refresh the selected report. A failed command never replaces the CRAP snapshot.
crap4ruby does not configure SimpleCov, delete reports, install dependencies, or select a test runner.

## Commands

| Option | Behavior |
| --- | --- |
| `--root PATH` | Set the project root; default is the current directory. |
| `--source-root PATH` | Search this directory; repeat for multiple roots. |
| `--changed` | Limit analysis to staged, unstaged, and untracked Git changes. |
| `--coverage PATH` | Read this SimpleCov resultset; default is `coverage/.resultset.json`. |
| `--use-existing-coverage` | Explicitly select the default: read reports without running tests. |
| `--coverage-command COMMAND` | Run a shell command that refreshes the selected report. |
| `--no-coverage` | Report complexity with unknown coverage and CRAP. |
| `--no-save` | Print results without creating or replacing `.metrics/crap.edn`. |
| `--threshold NUMBER` | Check this finite, nonnegative limit; exit 2 for a measured violation, or 1 if an unknown score could exceed it. |
| `-h`, `--help` | Print usage. |
| `-v`, `--version` | Print the gem version. |

Paths are relative to `--root`. Positional arguments select files or directories.
An argument that is not a path filters source paths by substring. Multiple filters use OR.
Explicit paths and source roots are combined; filters and `--changed` narrow that selection.

Discovery includes `.rb` files. It skips hidden directories, test/spec files, and these directories:
`test`, `tests`, `spec`, `features`, `vendor`, `node_modules`, `target`, `coverage`, `tmp`, `log`, `pkg`, `build`, and `dist`.
Test filenames are `test_*.rb`, `spec_*.rb`, `*_test.rb`, and `*_spec.rb`.
An explicitly named file overrides these exclusions. Directory traversal does not follow symbolic links.

Exit 0 means analysis succeeded and any requested threshold was verified. Exit 1 means invalid usage, unreadable or invalid input, a Git failure, a coverage command failure, or an uncertain threshold result.
Exit 2 means a measured score exceeded the threshold. A measured violation takes precedence over uncertainty. No threshold applies unless you set one.
Decimal thresholds are compared exactly with the computed scores, before display rounding.
For unknown scores, the check uses the maximum possible score, `CC^2 + CC`, at zero coverage. If this maximum fits the threshold, the method passes; otherwise, the check returns exit 1 and names the method. Its displayed score remains N/A. This also applies with `--no-coverage`.
For example, an unknown score at CC 2 passes a threshold of 6, but cannot pass a threshold of 5. Supply fresh, measurable coverage or adjust the limit to resolve uncertainty.
By default, every completed analysis replaces the snapshot, including filtered analyses, empty selections, and failed threshold checks.

For pre-commit or pre-push hooks that check complexity without tests or coverage, use:

```sh
bundle exec crap4ruby --no-coverage --no-save
```

`--no-save` preserves the terminal report and threshold exit codes while leaving the snapshot unchanged.
It also works with coverage enabled.

## Complexity and coverage

The scoring engine uses this formula, with coverage expressed as a fraction between 0 and 1:

```text
CRAP = CC^2 * (1 - coverage)^3 + CC
```

The formula follows the [original CRAP definition](https://www.artima.com/weblogs/viewpost.jsp?thread=210575). This tool uses line coverage as a proxy for the original definition's basis path coverage. These measurements are not equivalent.

Cyclomatic complexity (CC) follows [RuboCop 1.92.1](https://github.com/rubocop/rubocop/blob/aa228eb03094d66aca26664839ca14b10d76f702/lib/rubocop/cop/metrics/cyclomatic_complexity.rb). It starts at 1. Each of these adds 1:

- `if`, `elsif`, `unless`, and ternary conditions, including modifier forms.
- `while`, `until`, and `for` loops, except post-test `begin ... end while/until` forms.
- Each `when` or pattern-matching `in` clause. A pattern guard's `if`/`unless` wrapper adds nothing; decisions within its condition still count.
- Each rescue group, regardless of its number of clauses, and each rescue modifier.
- Each `&&`, `||`, `and`, `or`, `&&=`, and `||=` operation.
- Each safe-navigation operation, except repeated use of the same local receiver until its next assignment.
- Each ordinary block or block argument passed to a [known iteration method](https://github.com/rubocop/rubocop/blob/aa228eb03094d66aca26664839ca14b10d76f702/lib/rubocop/cop/metrics/utils/iterating_block.rb), such as `map`, `each`, or `reduce`.

A `when` clause adds 1 regardless of its number of alternatives. `else` and `ensure` add nothing.
Decisions inside ordinary blocks and lambdas belong to their enclosing method.
The method's own parameter defaults do not count. Nested definitions and their defaults, including nested class/module bodies, contribute decisions to the enclosing body, as in RuboCop.
The safe-navigation discount follows local variable names across that entire body, including nested scopes, in RuboCop's AST traversal order. Assignments reset it; parameters, pattern bindings, and named regexp captures do not.
RuboCop 1.92.1 does not add an iteration point for numbered or implicit-`it` blocks. This tool preserves that version's behavior. Iterator calls without a block add nothing.
Nested methods are also separate entries. Definitions inside parameter defaults and superclass expressions are discovered too.

Coverage is the fraction of executable method-body lines with positive hit counts.
Declaration lines and nested method/class/module bodies are excluded from coverage. Loading a definition does not prove that tests called its method.
When the body shares a line with its declaration, coverage and CRAP are N/A, even if that line has hits. This includes ordinary inline methods, one-line endless methods, and inline `define_method` blocks. Put the body on separate lines to obtain measurable coverage.
Coverage is also N/A when a selected body line contains trailing code after the definition, including enclosing delimiters that cannot be separated from that line's hit count. Put the closing delimiter on its own line. Comments and empty statement separators do not trigger this check.
Executable heredoc interpolation lines are included, even when the heredoc is the method's final expression.
Null lines do not enter the denominator. Multiple suites are merged by covered-line union, without applying an age cutoff.
Coverage paths must match absolute source paths or paths relative to the project root; unrelated checkout prefixes are not guessed.

A method with unambiguous body lines in a file absent from a valid report receives 0% coverage. A reported body with no measurable lines receives N/A.
Missing or malformed reports stop analysis unless `--no-coverage` is explicit.
Reports are accepted as supplied; generate fresh coverage after changing source files.

## Snapshot

The table lists the highest scores first, followed by entries with unknown scores.
The atomically replaced `.metrics/crap.edn` contains the same sorted entries, with coverage expressed as a percentage:

```clojure
{:entries [
  {:name "charge", :namespace "Billing::Invoice", :complexity 4, :coverage 50.0, :crap 6.0}
]}
```

Namespaces use Ruby's `::` separator. Top-level methods use `Object`.
Instance method names are `charge`; singleton method names are `self.charge`.
`--no-coverage` writes `nil` for both `:coverage` and `:crap`.

The shape matches crapper's snapshot. This gem does not add Ruby support to crapper or its consumers.
A filtered run writes only its selected methods. Reopened classes and repeated definitions can produce repeated namespace/name pairs.

## Limits

Analysis covers explicit method definitions, including private and endless methods, and bare `define_method` calls with one literal symbol/string name and a block.
Literal `define_method` names must be representable in UTF-8; unsupported names produce an error without replacing the previous snapshot.
It does not execute Ruby or resolve other runtime metaprogramming, dynamic `define_method` names, calls with explicit receivers, aliases, generated accessors, or dynamic singleton receivers.
Namespaces derived from expressions, such as `factory::Thing`, are skipped with their contents.
Line coverage cannot distinguish expressions sharing a source line or separate evaluation of default parameters.
Branch coverage is not used. Static namespace names do not reflect runtime constant reassignment.

These counting and threshold rules change results from 0.1.x and require a minor release under the versioning policy. Regenerate coverage and snapshots and review existing limits when upgrading.

## Development

```sh
bundle install
bundle exec rake
bundle exec ruby -Ilib exe/crap4ruby --help
```

The default task runs the tests with SimpleCov, then fails if any library method's CRAP score exceeds 10.
`bundle exec rake crap` runs the same check. `bundle exec rake test` runs only the tests and coverage collection.
Each Rake test run discards the previous resultset so stale coverage cannot improve the score.
Reports are written to `coverage/index.html`, `coverage/.resultset.json`, and `.metrics/crap.edn`.

The suite exercises real SimpleCov output and subprocess CLI behavior, in addition to parser and scoring fixtures.
See [CONTRIBUTING.md](CONTRIBUTING.md) for development guidance and [CHANGELOG.md](CHANGELOG.md) for changes.
The implementation is tested on CRuby 3.3, 3.4, and 4.0. Other Ruby implementations are unverified.

## Releases

The [versioning policy](VERSIONING.md) defines the public interface, version changes, and deprecation rules.

Signed `v*` tags trigger the release workflow. The tag must match `Crap4Ruby::VERSION`.
Tests and the CRAP limit run before the gem is built. Publication requires approval in GitHub's `release` environment.
RubyGems trusted publishing authenticates the workflow. Sigstore signs the built gem, and RubyGems stores its attestation.

Report defects or ask questions through [GitHub issues](https://github.com/svyatov/crap4ruby/issues).
Leonid Svyatov maintains this project. Security fixes target the latest release; see the [security policy](SECURITY.md).

## License

[MIT](LICENSE), copyright Leonid Svyatov.

Inspired by [crap4clj](https://github.com/unclebob/crap4clj), [crap4java](https://github.com/unclebob/crap4java), and [crap4go](https://github.com/unclebob/crap4go).
