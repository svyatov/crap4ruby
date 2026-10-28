# Contributing

Outside contributions are welcome. This guide defines the project's [acceptance criteria](#acceptance-criteria).

## Development

Use Ruby 3.3 or newer. Install [Betterleaks](https://github.com/betterleaks/betterleaks) with the `betterleaks` command on your PATH.
Set up dependencies and Git hooks, then run the suite:

```sh
bin/setup
bundle exec rake
```

Before each commit, hooks run Ruby lint checks and scan staged changes for secrets and whitespace errors.
Commit messages must use Conventional Commits.
Before each push, hooks run `bundle exec rake`.
Put machine-specific hook settings in the ignored `lefthook-local.yml` file.

The default check, also available as `bundle exec rake check`, runs RuboCop, Steep, tests with fresh SimpleCov coverage, YARD validation, and dependency audits.
Every Ruby file must have 100% typed calls.
Every library method's CRAP score must be at most 10.
Use `bundle exec rake test` for tests alone. Open `coverage/index.html` to inspect line coverage.

Run `bundle exec rake lint` to check Ruby style, formatting, performance, Minitest assertions, and Rake tasks.
Run `bundle exec rake format` to apply RuboCop's safe corrections, then review the diff.
RuboCop targets Ruby 3.3 and preserves the project's double-quoted strings and compact hashes.
YARD and CRAP enforce documentation and complexity requirements; RuboCop's overlapping documentation and metrics checks are disabled.

Run `bundle exec rake audit` to check both the development and release lockfiles for known vulnerabilities and insecure gem sources.
The audit updates RubySec's advisory database over the network and stores it in the ignored `.cache/` directory.
The default check and pre-push hook therefore require network access.

Run `bundle exec rake types` for type checks alone.
Keep library signatures in `sig/` and signatures for tests and development tools in `sig-development/`.
The type gate rejects unchecked Ruby files, untyped signatures, and any call that Steep cannot type.
Add new source locations to `Steepfile` when the gate reports an unchecked file.

Document public library methods and data readers with YARD summaries, parameter types, return types, and relevant exceptions.
Explain private methods when their constraints or side effects need context.
Keep types consistent with `sig/` and include examples when they clarify usage.
The Ruby reference is for maintainers and does not extend the [public compatibility policy](VERSIONING.md).

Run `bundle exec rake docs` to generate the reference, including private methods, then open `doc/index.html`.
Run `bundle exec rake docs:check` to reject YARD warnings, undocumented public methods, and readers without explicit documentation and return types.
Generated files in `doc/` and `.yardoc/` are ignored.

After changing dependencies, use Ruby 3.3 and the Bundler version recorded in `Gemfile.lock`.
Run `bundle exec rake lock` to refresh both lockfiles and their checksums.
CI installs the release tools from `gemfiles/release/Gemfile.lock` in frozen mode.

Add a regression test for a behavior change. Use temporary projects for filesystem, Git, coverage, and CLI tests.
Keep analyzed code out of the tool's process. Preserve the previous snapshot when analysis fails.

For defect reports, include the Ruby version, command, expected result, actual result, and a minimal source example.
Coverage defects also need a matching excerpt from `.resultset.json`. Remove application secrets before sharing examples.

Changes use Conventional Commits. Keep code, tests, and documentation for one behavior in a focused commit.

## Acceptance criteria

- Keep each change focused on one behavior or correction.
- Include tests for new functionality and regression tests for behavior changes.
- Pass `bundle exec rake`, including the method CRAP limit.
- Update documentation when user-visible behavior changes.
- Follow the [code of conduct](CODE_OF_CONDUCT.md).

## Submit a change

Fork the repository and create a branch from `main`. Commit your change, push the branch to your fork, and open a pull request against `svyatov/crap4ruby:main`.
Describe the behavior being changed and any effect on existing users. Link the related issue when one exists.

## Decisions and succession

Leonid Svyatov (@svyatov) is the sole maintainer and decides which changes to merge and release.
No succession arrangement exists if he stops maintaining the project.
