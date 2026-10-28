# Contributing

Use Ruby 3.3 or newer. Install dependencies and run the suite:

```sh
bundle install
bundle exec rake test
```

Add a regression test for a behavior change. Use temporary projects for filesystem, Git, coverage, and CLI tests.
Keep analyzed code out of the tool's process. Preserve the previous snapshot when analysis fails.

For defect reports, include the Ruby version, command, expected result, actual result, and a minimal source example.
Coverage defects also need a matching excerpt from `.resultset.json`. Remove application secrets before sharing examples.

Changes use Conventional Commits. Keep code, tests, and documentation for one behavior in a focused commit.
