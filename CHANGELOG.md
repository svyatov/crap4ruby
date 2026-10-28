# Changelog

## [Unreleased]

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
