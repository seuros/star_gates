# Changelog

## [0.3.2](https://github.com/seuros/star_gates/compare/v0.3.1...v0.3.2) (2026-11-08)


### Bug Fixes

* a feature timeout can no longer outlive the caller ([d9c108f](https://github.com/seuros/star_gates/commit/d9c108f1f47fd912ffed097ef9e70fff41078f35))
* a lone checkout can bundle ([90bb638](https://github.com/seuros/star_gates/commit/90bb638a78a33e4622c7ce459abbcd95bcf30bfc))
* a published flag value implies index membership ([3a60b40](https://github.com/seuros/star_gates/commit/3a60b4058d8ab5ce66643f479eb369c235803af4))
* bound the execution samples on the failure path too ([c516e97](https://github.com/seuros/star_gates/commit/c516e97542ab9d6a79c66f607c00eaa24ac3f542))
* check the budget before clamping it to a timeout ([6c7cc37](https://github.com/seuros/star_gates/commit/6c7cc37627adb295d30247a00c621b8956dbb765))
* measure latency with a t-digest instead of a trailing array ([f0e0beb](https://github.com/seuros/star_gates/commit/f0e0beb674a2bfd6097d1c104cd4cc927745bdc9))
* reclaim flag index slots instead of leaking them ([46002cc](https://github.com/seuros/star_gates/commit/46002ccb21188f6b8ac957bf50aaf570ae2e9cdb))
* replace deprecated ActiveSupport::Configurable with inheritable class config ([2a33f41](https://github.com/seuros/star_gates/commit/2a33f417f6d8d5a50e14deb2caee9b22d0fe3b1b))
* separate gate unavailability from the primary result ([85a1d35](https://github.com/seuros/star_gates/commit/85a1d352c0bbe2ee90923916de6d152ef7b625cb))

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
