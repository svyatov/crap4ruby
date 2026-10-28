# Changelog

All notable changes are recorded here using [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/).
Version numbers follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) as defined in the [versioning policy](VERSIONING.md).

## [Unreleased]

### Changed

- Use RuboCop 1.92.1 complexity rules, including iteration blocks, safe-navigation discounts, rescue groups, and nested bodies, while excluding a method's own parameter defaults.
- Discover bare `define_method` calls with literal symbol or string names and blocks.
- Reject literal `define_method` names that cannot be represented in UTF-8, preserving the previous snapshot.
- Report N/A for coverage and CRAP when a body shares its declaration line. Unknown scores pass a requested threshold only when their maximum possible score fits it; otherwise the check returns exit 1. These scoring and exit-code changes require a minor release. Regenerate coverage and snapshots and review thresholds when upgrading.

### Fixed

- Include executable interpolation lines when a method ends with a heredoc.
- Discover explicit method definitions inside parameter defaults and superclass expressions.
- Compare exact CRAP scores with decimal thresholds without floating-point rounding errors.
- Avoid attributing trailing code on a method's closing line to the method, and escape control characters in displayed method names.

## [0.1.1] - 2026-10-28

### Changed

- Document single-file analysis, contribution and private reporting policies, and the public compatibility policy.
- Add a YARD maintainer reference and link to gem documentation from RubyGems metadata.

## [0.1.0] - 2026-10-28

### Added

- Static Ruby method complexity analysis with Prism.
- SimpleCov line coverage, merged test suites, and CRAP scores.
- Source filters, Git change selection, explicit coverage commands, and optional score thresholds.
- Terminal reports and atomic snapshots compatible with crapper's EDN format.
- Permanent SimpleCov collection and a default Rake check enforcing a maximum method CRAP score of 10.

### Changed

- Split CLI execution, AST discovery, and coverage loading into smaller methods without changing their behavior or scoring rules.

[Unreleased]: https://github.com/svyatov/crap4ruby/compare/v0.1.1...HEAD
[0.1.1]: https://github.com/svyatov/crap4ruby/compare/v0.1.0...v0.1.1
[0.1.0]: https://github.com/svyatov/crap4ruby/releases/tag/v0.1.0
