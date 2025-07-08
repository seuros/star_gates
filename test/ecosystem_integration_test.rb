# frozen_string_literal: true

require 'test_helper'

# Ecosystem Integration: No defensive coding
# BreakerMachines, ChronoMachines, StateMachines all exist. Period.
class EcosystemIntegrationTest < Minitest::Test
  def test_breaker_machines_loaded
    # BreakerMachines IS the feature trip
    assert defined?(BreakerMachines), 'BreakerMachines not loaded'
    assert defined?(BreakerMachines::Circuit), 'BreakerMachines::Circuit missing'
  end

  def test_chrono_machines_loaded
    # ChronoMachines WAS CREATED for retry-jitter
    assert defined?(ChronoMachines), 'ChronoMachines not loaded'
    assert ChronoMachines.respond_to?(:retry), 'ChronoMachines.retry missing'
  end

  def test_state_machines_loaded
    # StateMachines gives BreakerMachines LIFE
    assert defined?(StateMachines), 'StateMachines not loaded - it gives BreakerMachines LIFE!'
  end

  def test_state_machines_powers_breaker_machines
    # StateMachines powers BreakerMachines state transitions
    circuit = StarGates::Circuit.new(threshold: 2, within: 30)

    # Circuit should have a breaker (BreakerMachines::Circuit)
    assert circuit.breaker, 'No breaker found'
    assert circuit.breaker.is_a?(BreakerMachines::Circuit), 'Breaker should be BreakerMachines::Circuit'

    # Breaker should have state management (powered by state_machines internally)
    assert circuit.breaker.respond_to?(:status), 'Breaker should have status'
    assert circuit.breaker.respond_to?(:open?), 'Breaker should have open?'
    assert circuit.breaker.respond_to?(:closed?), 'Breaker should have closed?'
    assert_equal 'closed', circuit.breaker.status, 'Initial state should be closed'
  end

  def test_chrono_machines_integrates_with_circuit
    call_count = 0
    circuit = StarGates::Circuit.new(
      threshold: 5,
      within: 30,
      retry_config: { max_attempts: 3, base_delay: 0.001 }
    )

    # Should use ChronoMachines for retry
    result = circuit.call do
      call_count += 1
      raise StandardError if call_count < 2

      'success'
    end

    assert_equal 'success', result
    assert_equal 2, call_count, 'ChronoMachines should have retried once'
  end

  def test_full_ecosystem_stack
    # BreakerMachines (circuit breaker) + ChronoMachines (retry jitter) + StateMachines (state)
    call_count = 0

    StarGates.define do
      gate :ecosystem_test do
        feature rollout: 100

        # BreakerMachines circuit with ChronoMachines retry
        circuit threshold: 3,
                within: 30.seconds,
                retry_config: { max_attempts: 3, base_delay: 0.001 }

        run do
          call_count += 1
          raise StandardError if call_count < 2

          'full stack works'
        end

        fallback { 'fallback' }
      end
    end

    gate = StarGates[:ecosystem_test]
    gate.feature.enable

    result = gate.call

    assert_equal 'full stack works', result
    assert_equal 2, call_count, 'Retry should have worked'

    # Circuit should be closed (BreakerMachines)
    assert gate.circuit.closed?, 'Circuit should be closed'

    # Feature should be enabled (StateMachines)
    assert gate.feature.enabled?, 'Feature should be enabled'
  end

  def test_breaker_machines_version
    version = Gem.loaded_specs['breaker_machines'].version
    assert version >= Gem::Version.new('0.5.0'), "BreakerMachines #{version} too old"
    puts "\n✅ BreakerMachines #{version} - Circuit breaker protection"
  end

  def test_chrono_machines_version
    version = Gem.loaded_specs['chrono_machines'].version
    assert version >= Gem::Version.new('0.3.0'), "ChronoMachines #{version} too old"
    puts "\n✅ ChronoMachines #{version} - Exponential backoff retry with jitter"
  end

  def test_ecosystem_hierarchy
    # StarGates orchestrates:
    #   ├── BreakerMachines (circuit breaker trip)
    #   │   └── StateMachines (gives it life)
    #   └── ChronoMachines (retry-jitter)

    circuit = StarGates::Circuit.new(
      threshold: 3,
      within: 30,
      retry_config: { max_attempts: 3 }
    )

    # Has BreakerMachines circuit
    assert circuit.breaker.is_a?(BreakerMachines::Circuit)

    # Has ChronoMachines retry policy
    assert circuit.retry_policy, 'No retry policy - ChronoMachines not integrated'

    # BreakerMachines uses StateMachines (status/open?/closed? are state machine methods)
    assert circuit.breaker.respond_to?(:status), 'BreakerMachines uses StateMachines for state'
    assert circuit.breaker.respond_to?(:open?), 'BreakerMachines has open? state check'
    assert circuit.breaker.respond_to?(:closed?), 'BreakerMachines has closed? state check'
  end
end
