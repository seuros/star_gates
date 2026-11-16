# StarGates

[![Gem Version](https://badge.fury.io/rb/star_gates.svg)](https://badge.fury.io/rb/star_gates)
[![Test](https://github.com/seuros/star_gates/actions/workflows/test.yml/badge.svg)](https://github.com/seuros/star_gates/actions/workflows/test.yml)

Feature flags, gradual rollouts, and circuit-protected execution for Ruby.
StarGates uses StateMachines for feature transitions, BreakerMachines for circuit
protection, ChronoMachines for retries, and DeadlineMachines for time budgets.

Time is Integer nanoseconds throughout: timeouts, cooldowns, backoffs, execution
times, and every reported instant (`StarGates.monotonic_time`; event-sourced events
use wall-clock nanoseconds, `StarGates.wall_time`). Wrong types raise `TypeError`,
values out of range `RangeError`.

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
Truthy strings are `true`, `1`, `yes`, and `on` (case-insensitive). A flag name is a
String or Symbol of letters, digits, `_`, or `-`: another type raises `TypeError`, another
String `RangeError`.

For Rails, keep defaults explicit and resolve them lazily:

```ruby
# config/initializers/feature_flags.rb
Rails.application.config.x.feature_flags = { copilot: true }
StarGates.flags.configuration = -> { Rails.application.config.x.feature_flags }
```

`StarGates::Flags.new(env: {}, configuration: {})` creates an isolated registry.
`all`, `enabled_flags`, `summary`, and `flag_status` expose values and their sources.
By default, runtime transitions reuse `StarGates::Feature`, and changes and metadata are
process-local. To share them across workers, give the registry an `ActiveSupport::Cache`
store (Solid Cache, Redis, Memcached):

```ruby
StarGates.flags.store = Rails.cache
# or: StarGates::Flags.new(store: Rails.cache, prefix: 'myapp:flags')
```

Store-backed flags read the store on every check, so a change in one worker is visible
in the others right away. Each flag's value and metadata are separate keys written
blindly; `prefix` (default `star_gates:flags`) namespaces them. A failed write raises
`StarGates::Error`, and a value the store cannot return counts as no runtime override.
Listing (`all`, `enabled_flags`, `summary`) and `reset!` use a shared name index. Each new
name takes its own slot from an atomic `increment`, so workers adding flags at the same
moment never drop each other's names; an `increment` that answers no Integer
(`NullStore` answers nil) raises `StarGates::Error` before anything is written. Stores
without `increment` fall back to a
read-modify-write list, where a concurrent addition can drop a name from listings until
that flag next changes; lookups by name are unaffected either way. `reset!` and `remove`
clear runtime state and metadata, not environment/configuration. Switching `store` drops
process-local runtime state.
`StarGates.reset!` resets gates separately.

## Gates and rollouts

```ruby
NS_PER_SECOND = 1_000_000_000

# Open after 3 failures within a minute; probe again after 30 seconds.
PAYMENTS_POLICY = BreakerMachines::Policy.new(
  BreakerMachines::Threshold.new(3, nil, 0), 60 * NS_PER_SECOND,
  BreakerMachines::Recovery.new(30 * NS_PER_SECOND, 0.0, 1, 1), nil
)

StarGates.define do
  gate :payments do
    feature rollout: 25.percent
    circuit PAYMENTS_POLICY

    run { |context| PaymentAPI.charge(context[:amount]) }
    fallback { |context| LegacyPaymentAPI.charge(context[:amount]) }
  end
end

gate = StarGates[:payments]
gate.feature.rollout_canary
gate.call(key: 'account:42', amount: 100)
```

Features start disabled. Use `rollout_canary` for percentage/group targeting,
`enable` for full rollout, and `disable` to turn a feature off. An event
answers the performed transition, or `false` when refused, with the reason in
`<event>_refusal` (`gate.feature.disable_refusal # => :no_transition`); the
bang forms (`enable!`, ...) raise `StateMachines::InvalidTransition` carrying
it in `#reason`. Pass a stable
string or integer `key:` for percentage targeting, such as an account, resident,
or device identifier.

Percentage targeting stays consistent across workers and restarts. Increasing
the rollout percentage retains keys already included.

For group targeting, pass `groups: [:beta]` to match `feature group: :beta`.
A predicate such as `feature group: ->(context) { context[:region] == 'eu' }`
receives the full context passed to the gate.

A rollout is an Integer percentage, 0..100; a group is a Symbol or a Proc.

`circuit` takes a `BreakerMachines::Policy` and an optional `StarGates::RetryPolicy`,
positionally, as `StarGates::Circuit.new(policy, retry_policy, feature:, auto_rollback:)`
does; `feature:` and `auto_rollback:` are runtime-only. When a circuit opens, its
feature rolls back from enabled to canary, or from canary to disabled.

Gates use their fallback when the primary is unavailable. Without a fallback, `call`
raises `StarGates::UnavailableError`, whose `refusal` says why: `:ineligible` (the
feature is off for this context), `:failed` (the primary raised; it is the `cause`),
`:exceeded` (the time budget ran out), or the circuit's own refusal (`:open`, `:busy`,
`:full`).

### Retries

A `RetryPolicy` is a ChronoMachines strategy and an attempt budget that counts the
first try, in `ChronoMachines::Retry`'s order:

```ruby
backoff = ChronoMachines::Exponential.new(100_000_000, 2.0, 5 * NS_PER_SECOND, 1.0)
circuit PAYMENTS_POLICY, StarGates::RetryPolicy.new(backoff, 3)
```

Retries are opt-in. A call the circuit refuses is never retried: the refusal is the
answer. Exhausted retries re-raise the last exception.

### Timeouts

`ApplicationStarGate` features take `timeout:` in Integer nanoseconds, narrowed by
the ambient `DeadlineMachines` budget. A spent budget does not run the block.

### Event sourcing

`StarGates.configure_foundation` wires an event store, repository, and projection.
Commands answer the aggregate or a refusal symbol and change nothing:
`:not_found`, `:invalid_transition`, `:stale_state` (the feature is not in the
`from_state` given), `:version_conflict` (a concurrent writer saved first).
States and event names are Symbols; a String is a `TypeError` and changes nothing.
The projection reads the same through any adapter (Symbol keys and state names, even
from Redis's JSON). `StarGates.recent_transitions` answers
`{ transitions:, total_found:, limit:, generated_at: }` with event sourcing on or off,
and every transition is `{ feature:, from:, to:, event:, occurred_at: }` in both
modes: `feature` the String feature id (the gate name without event sourcing),
`from`, `to` and `event` Symbols, `occurred_at` wall-clock Integer nanoseconds.

With jsonrpc-rails, include `StarGates::JsonrpcRailsAdapter` in a controller and route
to its `handle_jsonrpc` action (`post '/jsonrpc', to: 'features#handle_jsonrpc'`). The
adapter defines no method Rails' controllers already have, so `process` and the rest of
the dispatch stay Rails'.

## Rails

Define gates in an initializer and call them from controllers or services:

```ruby
class PaymentsController < ApplicationController
  def create
    result = StarGates[:payments].call(key: "account:#{current_account.id}", amount: params[:amount])
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
`circuit.recovered`, and `circuit.retry` (`next_delay` in nanoseconds), prefixed with
`star_gates.`. Telemetry adapters take durations in nanoseconds; the Prometheus
adapter reports seconds, its base unit.

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
ship.engage_warp('Alpha Centauri', key: 'crew:1', groups: [:pilots])
```

### Application examples

- [Payment feature](test/dummy/demos/payment_feature.rb): state-specific feature behavior.
- [Transition history](test/dummy/demos/transition_demo.rb): recorded feature transitions.
- [Introspection](test/dummy/demos/introspection_demo.rb): status, analytics, and context simulation.
- [Application payment feature](test/dummy/demos/application_payment_feature.rb): application-level features.

Run standalone examples from the repository root:

```sh
bundle exec ruby test/dummy/demos/payment_feature.rb
```

## Development

```sh
bin/setup
bundle exec rake test
bundle exec rake test:rails
bundle exec rake rbs
dictator lint .
```

The Gemfile resolves released sibling gems. To test against sibling checkouts, put
`gem 'breaker_machines', path: '../breaker_machines'` (and the others) in an
untracked `Gemfile.local`, which the Gemfile evaluates when present, and compile each
sibling's extension in its own tree first (`bundle exec rake compile`).

Tests run with padded_cell and Minitest 6. Gem tests and Rails integration tests
run in separate processes. `bundle exec rake` runs both suites. To select gem tests
directly or pass runner options:

```sh
bundle exec padded_cell test/gate_test.rb
bundle exec rake test TESTOPTS='-j 4 --seed 1234'
```

See [CHANGELOG.md](CHANGELOG.md) for release history.

## 📡 Credits

**AMS Fowler**, NCC-2010, *Fowler*-class gatekeeper.

Named for Martin Fowler's *FeatureToggle* (2010), the note that gave feature
flags a name and the warning that came with it: every toggle is debt until it
is removed.

## License

[BSD-3-Clause](LICENSE.txt).

> In space, nobody can hear your feature flags fail, but they'll notice when your fleet survives.
