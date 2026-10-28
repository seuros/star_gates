# Changelog

## Unreleased

### Changed

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
