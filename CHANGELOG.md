# Changelog

## [0.3.1](https://github.com/seuros/star_gates/compare/v0.3.0...v0.3.1) (2026-10-30)


### Bug Fixes

* **deps:** require breaker_machines 0.22.1 ([34c4f16](https://github.com/seuros/star_gates/commit/34c4f16849e89646e38b73fb846049d1fcffb762))

## [0.3.0](https://github.com/seuros/star_gates/compare/v0.2.0...v0.3.0) (2026-10-30)


### Features

* share runtime flags through an ActiveSupport::Cache store ([edb39ba](https://github.com/seuros/star_gates/commit/edb39ba43f03278a6e3d70770a14671ccc4eb539))

## 0.2.0 (2026-10-28)

### Changed

- Use explicit rollout `key:` and `groups:` context. Group predicates receive the
  full context; simulation, debugging, and scenario analysis use key-based inputs
  and results. Remove user-specific helpers and telemetry labels.
- Require Ruby 4.0 or newer.
- Require StateMachines 0.202.0 or newer.
- Change the license to BSD-3-Clause.
- Use ActiveSupport duration helpers without overriding Rails behavior.
- Preserve fractional seconds in circuit cooldowns and failure windows.
- Consolidate documentation and remove generated repository artifacts, keeping the space-fleet examples.
- Move demos into the Rails dummy app and rewrite ship systems as StarGates gates.
- Run gem and Rails integration tests separately, with explicit test discovery and Rails setup.
- Use the Dictator GitHub Action and a project decree for structural linting.
- Run both test suites with padded_cell and Minitest 6.

### Fixed

- Keep percentage rollout cohorts stable across workers and restarts with CRC32
  key buckets. Upgrading reassigns cohorts previously based on Ruby's
  process-randomized string hashes.
- Correct dummy-app feature routing, persistent feature transitions, and circuit statistics.
- Make weather demo failures explicit instead of random.

### Added

- Boolean flags with environment, configuration, and runtime overrides.
- Flag status, metadata, and debugging helpers.

## 0.1.0 (2025-10-30)

### Security

- Use safe YAML loading for configuration files.

### Fixed

- Correct percentage-string parsing for feature rollouts.
- Remove dead time-parsing code.

### Added

- ChronoMachines retry policies with exponential backoff and jitter.
- Circuit retry instrumentation.
- Feature state transitions, rollout targeting, and automatic circuit-triggered rollback.
- Transition history and introspection.
- Regression coverage for configuration security, rollouts, concurrency, and retries.

### Changed

- Use immutable `Data.define` mock users instead of `OpenStruct`.
- Use concurrent-ruby primitives for thread-safe registries and transition history.

## 0.0.0

- Internal development version.
