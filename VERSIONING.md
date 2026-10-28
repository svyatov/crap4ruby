# Versioning policy

crap4ruby uses [Semantic Versioning 2.0.0](https://semver.org/spec/v2.0.0.html) for its documented public interface.

## Public interface

The compatibility policy covers:

- Documented CLI options, positional file selection, and exit codes.
- Documented complexity, coverage, and CRAP scoring semantics.
- The `.metrics/crap.edn` schema, including field meanings and value types.
- The minimum supported Ruby version.

Terminal table spacing, diagnostic wording, and Ruby classes are implementation details.
YARD documents the Ruby interfaces for maintainers; those interfaces are outside this compatibility policy.
Use the CLI and documented snapshot format when integrating with other tools.

## Version changes

During initial development (`0.y.z`), incompatible public changes increase MINOR. Compatible additions, fixes, and deprecations increase PATCH.
Starting with `1.0.0`, incompatible public changes increase MAJOR, compatible additions and deprecations increase MINOR, and compatible fixes increase PATCH.

Each release tag, gem version, and changelog entry must identify the same version. Published versions are never replaced.
Documentation and CI maintenance alone do not require a release.

## Deprecation

Deprecate a public interface in a release before removing it in a later release.
The notice must name its replacement or migration path and the earliest removal version, using a CLI diagnostic where applicable.
Removal requires a later MINOR release during initial development or a later MAJOR release after `1.0.0`.
