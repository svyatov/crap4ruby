# Changelog

All notable changes are recorded here using [Keep a Changelog 2.0.0](https://keepachangelog.com/en/2.0.0/).
Version numbers follow [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) as defined in the [versioning policy](VERSIONING.md).

## [Unreleased]

### Changed

- Document single-file analysis, contribution and private reporting policies, and the public compatibility policy.

## [0.1.0] - 2026-10-28

### Added

- Static Ruby method complexity analysis with Prism.
- SimpleCov line coverage, merged test suites, and CRAP scores.
- Source filters, Git change selection, explicit coverage commands, and optional score thresholds.
- Terminal reports and atomic snapshots compatible with crapper's EDN format.
- Permanent SimpleCov collection and a default Rake check enforcing a maximum method CRAP score of 10.

### Changed

- Split CLI execution, AST discovery, and coverage loading into smaller methods without changing their behavior or scoring rules.

[Unreleased]: https://github.com/svyatov/crap4ruby/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/svyatov/crap4ruby/releases/tag/v0.1.0
