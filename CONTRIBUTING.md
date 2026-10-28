# Contributing

Outside contributions are welcome. This guide defines the project's [acceptance criteria](#acceptance-criteria).

## Development

Use Ruby 3.3 or newer. Install dependencies and run the suite:

```sh
bundle install
bundle exec rake
```

The default check runs Steep, requires 100% typed calls across every Ruby file, and runs tests with fresh SimpleCov coverage.
Every library method's CRAP score must be at most 10.
Use `bundle exec rake test` for tests alone. Open `coverage/index.html` to inspect line coverage.

Run `bundle exec rake types` for type checks alone.
Keep library signatures in `sig/` and signatures for tests and development tools in `sig-development/`.
The type gate rejects unchecked Ruby files, untyped signatures, and any call that Steep cannot type.
Add new source locations to `Steepfile` when the gate reports an unchecked file.

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
