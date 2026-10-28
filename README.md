# StarGates

[![Gem Version](https://badge.fury.io/rb/star_gates.svg)](https://badge.fury.io/rb/star_gates)
[![CI](https://github.com/seuros/star_gates/actions/workflows/ci.yml/badge.svg)](https://github.com/seuros/star_gates/actions/workflows/ci.yml)

Feature flags, gradual rollouts, and circuit-protected execution for Ruby.
StarGates uses StateMachines for feature transitions, BreakerMachines for circuit
protection, and ChronoMachines for retries.

## Installation

Requires **Ruby 4.0+** and **ActiveSupport 8.1.1+**. Rails is optional.

```ruby
gem 'star_gates'
```

```sh
bundle install
```

## Boolean flags

```ruby
require 'star_gates'

StarGates.flags.configuration = { copilot: true }
StarGates.flags.enabled?(:copilot)
StarGates.flags.enable(:preview, metadata: { reason: 'testing' })
StarGates.flags.disable(:preview)
StarGates.flags.debug(:preview)
StarGates.flags.reset!
```

Precedence: nonblank `FEATURE_<NAME>` environment variable, boolean configuration,
runtime override, then `false`. Names are case-insensitive; dashes become underscores.
Truthy strings are `true`, `1`, `yes`, and `on` (case-insensitive).

For Rails, keep defaults explicit and resolve them lazily:

```ruby
# config/initializers/feature_flags.rb
Rails.application.config.x.feature_flags = { copilot: true }
StarGates.flags.configuration = -> { Rails.application.config.x.feature_flags }
```

`StarGates::Flags.new(env: {}, configuration: {})` creates an isolated registry.
`all`, `enabled_flags`, `summary`, and `flag_status` expose values and their sources.
Runtime transitions reuse `StarGates::Feature`; changes and metadata are process-local,
not persisted or synchronized across workers. `reset!` clears both runtime state and
metadata, not environment/configuration. `StarGates.reset!` resets gates separately.

## Gates and rollouts

```ruby
StarGates.define do
  gate :payments do
    feature rollout: 25.percent
    circuit threshold: 3, within: 1.minute, reset_after: 30.seconds

    run { |context| PaymentAPI.charge(context[:amount]) }
    fallback { |context| LegacyPaymentAPI.charge(context[:amount]) }
  end
end

gate = StarGates[:payments]
gate.feature.rollout_canary
gate.call(user: current_user, amount: 100)
```

Features start disabled. Use `rollout_canary` for percentage/group targeting,
`enable` for full rollout, and `disable` to turn a feature off. Provide a user with
an `id` for consistent percentage targeting.

When a circuit opens, its feature rolls back from enabled to canary, or from canary
to disabled. Gates use their fallback when the feature is unavailable or execution
fails. Rails duration helpers retain their normal behavior, including fractional
seconds such as `0.5.seconds`.

### Retries

Pass `retry_config` to a gate's `circuit` declaration:

```ruby
circuit threshold: 5,
        within: 1.minute,
        retry_config: {
          max_attempts: 3,
          base_delay: 0.1,
          multiplier: 2,
          max_delay: 5
        }
```

Retries are opt-in and use ChronoMachines.

## Rails

Define gates in an initializer and call them from controllers or services:

```ruby
class PaymentsController < ApplicationController
  def create
    result = StarGates[:payments].call(user: current_user, amount: params[:amount])
    render json: result
  end
end
```

The Rails integration fixture lives in `test/dummy/` and uses the root Gemfile.

## Instrumentation

StarGates emits events through `ActiveSupport::Notifications`:

```ruby
ActiveSupport::Notifications.subscribe('star_gates.circuit.auto_rollback') do |*args|
  event = ActiveSupport::Notifications::Event.new(*args)
  Rails.logger.warn(event.payload)
end
```

Circuit events include `circuit.auto_rollback`, `circuit.half_open`,
`circuit.recovered`, and `circuit.retry`, prefixed with `star_gates.`.

## Examples

### Space fleet

All demos live in `test/dummy/`. The fleet uses real `StarGates::Gate` instances
for feature rollout, circuit protection, automatic rollback, and fallbacks.
BreakerMachines is the underlying circuit engine, not a separate ship API.

- [Spaceship](test/dummy/app/models/spaceship.rb): warp drive, fusion reactor, and navigation circuits.
- [Spaceflight systems](test/dummy/app/models/spaceflight_systems.rb): simulated ship subsystems.
- [Ship hierarchy](test/dummy/app/models/base_ship.rb): shared systems for the fleet.
- [Corellian freighter](test/dummy/app/models/corellian_freighter.rb): specialized ship behavior.
- [RMNS Atlas Monkey](test/dummy/app/models/rmns_atlas_monkey.rb): the Universal Commentary Engine.

Run the fleet demo without starting Rails:

```sh
bundle exec ruby test/dummy/demos/space_fleet.rb
```

It demonstrates disabled-system fallback, pilot-only canary access, full rollout,
hardware failures opening a circuit, automatic feature rollback, and explicit
operator-approved recovery. Each ship's gates have independent state.

```ruby
require_relative 'test/dummy/app/models/spaceship'

ship = Spaceship.new('SG Atlas', 'SG-1')
warp = ship.gate(:warp_drive) # A StarGates::Gate, with a feature and a circuit.
warp.feature.rollout_canary
pilot = StarGates::Feature::MockUser.new(id: 1, groups: [:pilots])
ship.engage_warp('Alpha Centauri', pilot: pilot)
```

### Application examples

- [Payment feature](test/dummy/demos/payment_feature.rb): state-specific feature behavior.
- [Transition history](test/dummy/demos/transition_demo.rb): recorded feature transitions.
- [Introspection](test/dummy/demos/introspection_demo.rb): status, analytics, and user simulation.
- [Application payment feature](test/dummy/demos/application_payment_feature.rb): application-level features.
- [JSON-RPC controller](test/dummy/demos/jsonrpc_rails_controller.rb): optional JSON-RPC integration.

Run standalone examples from the repository root:

```sh
bundle exec ruby test/dummy/demos/payment_feature.rb
```

## Development

```sh
bin/setup
bundle exec rake test
bundle exec rake test:rails
dictator lint .
```

Gem tests and Rails integration tests run in separate processes. `bundle exec rake`
runs both suites. To run only the gem tests:

```sh
bundle exec ruby -Itest -e 'Dir["test/*_test.rb"].sort.each { |file| require_relative file }'
```

See [CHANGELOG.md](CHANGELOG.md) for release history.

## License

[BSD-3-Clause](LICENSE.txt).

> In space, nobody can hear your feature flags fail, but they'll notice when your fleet survives.
