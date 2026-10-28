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
gem install ./crap4ruby-0.1.1.gem
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
| `--threshold NUMBER` | Exit 2 when any unrounded score exceeds this finite, nonnegative value. |
| `-h`, `--help` | Print usage. |
| `-v`, `--version` | Print the gem version. |

Paths are relative to `--root`. Positional arguments select files or directories.
An argument that is not a path filters source paths by substring. Multiple filters use OR.
Explicit paths and source roots are combined; filters and `--changed` narrow that selection.

Discovery includes `.rb` files. It skips hidden directories, test/spec files, and these directories:
`test`, `tests`, `spec`, `features`, `vendor`, `node_modules`, `target`, `coverage`, `tmp`, `log`, `pkg`, `build`, and `dist`.
Test filenames are `test_*.rb`, `spec_*.rb`, `*_test.rb`, and `*_spec.rb`.
An explicitly named file overrides these exclusions. Directory traversal does not follow symbolic links.

Exit 0 means analysis succeeded. Exit 1 means invalid usage, unreadable or invalid input, a Git failure, or a coverage command failure.
Exit 2 means analysis succeeded but exceeded the threshold. No threshold applies unless you set one.
Every successful analysis replaces the snapshot, including filtered analyses and empty selections.

## Complexity and coverage

The scoring engine uses this formula, with coverage expressed as a fraction between 0 and 1:

```text
CRAP = CC^2 * (1 - coverage)^3 + CC
```

Cyclomatic complexity (CC) starts at 1. Each of these adds 1:

- `if`, `elsif`, `unless`, and ternary conditions, including modifier forms.
- `while`, `until`, and `for` loops.
- Each `when` or pattern-matching `in` clause, including a separate increment for a guard condition.
- Each rescue clause and rescue modifier.
- Each `&&`, `||`, `and`, `or`, `&&=`, `||=`, and safe-navigation operation.

A `when` clause adds 1 regardless of its number of alternatives. `else` and `ensure` add nothing.
Decisions inside ordinary blocks and lambdas belong to their enclosing method.
Decisions in parameter defaults also count; coverage still measures only the body.
Nested methods are separate entries. Their bodies and nested class/module bodies do not increase the enclosing method's score.
Calling `each`, `map`, or another iterator does not itself add complexity.

Coverage is the fraction of executable method-body lines with positive hit counts.
Separate `def` headers are excluded: loading a definition does not prove that tests called its method.
Null lines do not enter the denominator. Multiple suites are merged by covered-line union, without applying an age cutoff.
Coverage paths must match absolute source paths or paths relative to the project root; unrelated checkout prefixes are not guessed.

A method absent from a valid report receives 0% coverage. A body with no measurable lines receives N/A.
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

Analysis covers explicit method definitions, including private and endless methods.
It does not execute Ruby or resolve runtime metaprogramming, `define_method`, aliases, generated accessors, or dynamic singleton receivers.
Namespaces derived from expressions, such as `factory::Thing`, are skipped with their contents.
Line coverage cannot distinguish expressions or methods sharing a source line, or separate evaluation of default parameters.
Branch coverage is not used. Static namespace names do not reflect runtime constant reassignment.

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
