# StarGates

[![Gem Version](https://badge.fury.io/rb/star_gates.svg)](https://badge.fury.io/rb/star_gates)
[![Build Status](https://github.com/seuros/star_gates/workflows/CI/badge.svg)](https://github.com/seuros/star_gates/actions)
[![Coverage Status](https://coveralls.io/repos/github/seuros/star_gates/badge.svg?branch=master)](https://coveralls.io/github/seuros/star_gates?branch=master)
[![Ruby Style Guide](https://img.shields.io/badge/code_style-rubocop-brightgreen.svg)](https://github.com/rubocop/rubocop)

> **Quantum State Machines for Ruby** 🌌

StarGates provides next-generation state machine management for Ruby, with advanced patterns for distributed systems that actually work.

---

## 📚 Table of Contents

* [Installation](#installation)
* [Usage](#usage)
* [Key Features](#key-features)
* [Advanced Patterns](#advanced-patterns)
* [Architecture](#architecture)
* [Documentation](#documentation)
* [Contributing](#contributing)
* [License](#license)
* [Lore & Easter Eggs](#lore--easter-eggs)

---

## 🚀 Installation

Add StarGates to your Gemfile:

```ruby
gem 'star_gates'
```

Then install:

```bash
bundle install
```

Or install directly via:

```bash
gem install star_gates
```

---

## 💡 Usage

### Rails Integration

```ruby
class PaymentController < ApplicationController
  include StarGates::DSL

  gate :stripe_v2 do
    feature rollout: 25.percent, group: :beta_users
    circuit threshold: 3, within: 1.minute, reset_after: 30.seconds

    run { process_stripe_v2_payment }
    fallback { process_legacy_payment }
  end

  def charge
    activate(:stripe_v2, context: { user: current_user })
  end
end
```

### Plain Ruby

```ruby
require 'star_gates'

class PaymentService
  include StarGates::DSL

  gate :stripe_api do
    feature rollout: 50.percent
    circuit threshold: 5, within: 2.minutes, reset_after: 1.minute

    run { call_stripe_api }
    fallback { queue_for_later }
  end

  def process_payment
    activate(:stripe_api, context: { user_id: user.id })
  end

  private

  def call_stripe_api
    # Implement Stripe API call
  end

  def queue_for_later
    # Implement fallback logic
  end
end
```

---

## 🛠 Key Features

* **State Machine-driven** feature lifecycle
* **Circuit Breaker protection** for stability
* **Context-aware rollouts** (user, geography, time)
* **Automatic rollback** when circuits trip
* **Multi-dimensional gates** (mobile, desktop, A/B)
* **Cost-aware throttling** with budget monitoring
* **Dark launch capabilities** for silent testing
* **Quantum feature states** (superposition until user interaction)
* **Self-healing rollouts** via ML-driven optimization
* **ActiveSupport::Notifications** integration for instrumentation

---

## 🌟 Advanced Patterns

Explore powerful, real-world scenarios:

* **Quantum Feature States**: Feature states remain in superposition until interacted with.
* **Inter-Feature Symbiosis**: Manage features with dependencies or conflicts dynamically.
* **Temporal Rollouts**: Schedule feature activations with built-in safety mechanisms.
* **Geo-Adaptive Rollouts**: Regional control with automated fallbacks.
* **Self-Healing Rollouts**: Intelligent recovery using ML insights.

Detailed examples in [Advanced Patterns](docs/ADVANCED_PATTERNS.md).

---

## ⚙️ Architecture

```
StateMachines (proven state management)
    ↓
BreakerMachines (robust circuit breaker protection)
    ↓
StarGates (quantum feature orchestration)
```

StarGates leverages evolutionary architecture—each layer enhancing the proven patterns of its predecessors to deliver robust, intelligent feature flag orchestration.

---

## 📖 Documentation

* [Getting Started](docs/GETTING_STARTED.md)
* [State Machines](docs/STATE_MACHINES.md)
* [Circuit Breakers](docs/CIRCUIT_BREAKERS.md)
* [Context-Aware Gates](docs/CONTEXT_AWARE.md)
* [Self-Healing Systems](docs/SELF_HEALING.md)
* [Testing Guide](docs/TESTING.md)
* [Rails Integration](docs/RAILS_INTEGRATION.md)
* [Horror Stories & Lessons](docs/HORROR_STORIES.md)

---

## 🤝 Contributing

1. Fork the repo
2. Create your feature branch (`git checkout -b feature/your-feature`)
3. Commit your changes (`git commit -am 'Add my feature'`)
4. Push (`git push origin feature/your-feature`)
5. Submit a Pull Request for review by the Resistance Elders

---

## 📜 License

StarGates is MIT licensed. See [LICENSE](LICENSE) for details.

---

## 🧩 Lore & Easter Eggs

### The Resistance

Welcome to the future—feature flags aren't boolean switches; they're sophisticated state machines guarded by circuit breakers. This isn't just a configuration change—it's survival.

### Stardate 2025.186

Production is chaos, flags are failing. A junior developer writes technical debt disguised as gradual rollout logic:

```ruby
def new_dashboard_enabled?
  if Rails.env.production?
    return false if Time.current.hour < 9 || Time.current.hour > 17
    return false if current_user.created_at > 1.week.ago
    return true if current_user.admin?
    rand(100) < 25 # YOLO
  else
    true
  end
end
```

“This is how it starts,” warns the Ops veteran. StarGates prevents this nightmare.

### Reality Check

* **You think**: "Gradual rollouts ensure safety."
* **Reality**: Without StarGates, your "safe" rollouts spiral into distributed chaos.

See [Death Spiral Diagram](docs/DIAGRAMS.md#the-percentage-rollout-death-spiral).

---

**"In space, nobody can hear your feature flags fail—but they'll notice when your fleet survives the anti-matter pulse."

— RMNS Atlas Monkey**
