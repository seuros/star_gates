# frozen_string_literal: true

require 'test_helper'

# Self-Healing Feature Flag Tests
# StarGates automatically rolls back features when circuit breakers detect failures
class SelfHealingTest < Minitest::Test
  # ===========================================================================
  # SELF-HEALING: Automatic Rollback on Circuit Open
  # ===========================================================================

  def test_circuit_open_triggers_rollback_enabled_to_canary
    feature = StarGates::Feature.new(rollout: 50)
    feature.enable

    circuit = StarGates::Circuit.new(
      threshold: 2,
      within: 30,
      feature: feature,
      auto_rollback: true
    )

    # Initial state: enabled
    assert_equal 'enabled', feature.status

    # Trigger failures to open circuit
    2.times do
      assert_raises(StandardError) do
        circuit.call { raise StandardError, 'service failure' }
      end
    end

    # Circuit should open
    assert circuit.open?, 'Circuit should be open after threshold failures'

    # Feature should auto-rollback: enabled → canary
    assert_equal 'canary', feature.status, 'Feature should auto-rollback to canary'
  end

  def test_circuit_open_triggers_rollback_canary_to_disabled
    feature = StarGates::Feature.new(rollout: 50)
    feature.rollout_canary

    circuit = StarGates::Circuit.new(
      threshold: 2,
      within: 30,
      feature: feature,
      auto_rollback: true
    )

    # Initial state: canary
    assert_equal 'canary', feature.status

    # Trigger failures to open circuit
    2.times do
      assert_raises(StandardError) do
        circuit.call { raise StandardError, 'service failure' }
      end
    end

    # Circuit should open
    assert circuit.open?, 'Circuit should be open'

    # Feature should auto-rollback: canary → disabled
    assert_equal 'disabled', feature.status, 'Feature should auto-rollback to disabled'
  end

  def test_auto_rollback_disabled_when_flag_false
    feature = StarGates::Feature.new(rollout: 50)
    feature.enable

    circuit = StarGates::Circuit.new(
      threshold: 2,
      within: 30,
      feature: feature,
      auto_rollback: false # Disable auto-rollback
    )

    # Initial state: enabled
    assert_equal 'enabled', feature.status

    # Trigger failures to open circuit
    2.times do
      assert_raises(StandardError) do
        circuit.call { raise StandardError, 'service failure' }
      end
    end

    # Circuit should open
    assert circuit.open?

    # Feature should NOT auto-rollback
    assert_equal 'enabled', feature.status, 'Feature should remain enabled when auto_rollback is false'
  end

  def test_auto_rollback_instrumentation_events
    feature = StarGates::Feature.new(rollout: 50)
    feature.enable

    circuit = StarGates::Circuit.new(
      threshold: 2,
      within: 30,
      feature: feature,
      auto_rollback: true
    )

    events = []
    subscriber = lambda { |name, _start, _finish, _id, payload|
      events << { name: name, payload: payload }
    }

    begin
      ActiveSupport::Notifications.subscribe('star_gates.circuit.auto_rollback', &subscriber)

      # Trigger failures
      2.times do
        assert_raises(StandardError) do
          circuit.call { raise StandardError, 'failure' }
        end
      end

      # Should have instrumentation event
      rollback_event = events.find { |e| e[:name] == 'star_gates.circuit.auto_rollback' }
      assert rollback_event, 'Should emit circuit.auto_rollback event'
      assert_equal 'enabled', rollback_event[:payload][:feature_status]
      assert_equal 'open', rollback_event[:payload][:circuit_state]
      assert_equal 'rolling_back', rollback_event[:payload][:action]
    ensure
      ActiveSupport::Notifications.unsubscribe('star_gates.circuit.auto_rollback')
    end
  end

  # ===========================================================================
  # SELF-HEALING: Integration with DSL
  # ===========================================================================

  def test_dsl_gates_have_self_healing_enabled
    StarGates.reset!

    StarGates.define do
      gate :payment_api do
        feature rollout: 50.percent
        circuit threshold: 3, within: 1.minute

        run { raise StandardError, 'API failure' } # Must raise to trigger circuit
        fallback { 'fallback' }
      end
    end

    gate = StarGates[:payment_api]
    feature = gate.feature

    # Enable feature
    feature.enable
    assert_equal 'enabled', feature.status

    # Trigger failures by calling the gate (run block raises)
    3.times { gate.call }

    # Feature should auto-rollback
    assert_equal 'canary', feature.status, 'DSL gates should have auto-rollback enabled'
  end

  def test_full_self_healing_sequence
    feature = StarGates::Feature.new(rollout: 50)
    feature.enable

    # Use shorter reset_after for test speed
    circuit = StarGates::Circuit.new(
      threshold: 3,
      within: 30,
      reset_after: 1, # 1 second reset
      feature: feature,
      auto_rollback: true
    )

    # Track state transitions
    states = [feature.status]

    # Trigger failures → should rollback enabled → canary
    3.times do
      assert_raises(StandardError) do
        circuit.call { raise StandardError }
      end
    end

    states << feature.status
    assert_equal %w[enabled canary], states, 'Should transition enabled → canary'

    # Feature is now in canary, need to wait for circuit to half-open, then fail again
    # to trigger another auto-rollback
    states.clear
    states << feature.status

    # Wait for reset timeout to enter half-open
    sleep 1.5

    # Fail again in half-open state → circuit will open again → on_open triggers rollback
    3.times do
      assert_raises(StandardError) do
        circuit.call { raise StandardError }
      end
    end

    states << feature.status
    assert_equal %w[canary disabled], states, 'Should transition canary → disabled'
  end

  # ===========================================================================
  # SELF-HEALING: Circuit Recovery
  # ===========================================================================

  def test_circuit_close_instrumentation
    feature = StarGates::Feature.new(rollout: 50)
    circuit = StarGates::Circuit.new(
      threshold: 2,
      within: 30,
      reset_after: 1, # 1 second reset
      feature: feature,
      auto_rollback: true
    )

    events = []
    subscriber = lambda { |name, _start, _finish, _id, payload|
      events << { name: name, payload: payload }
    }

    begin
      ActiveSupport::Notifications.subscribe('star_gates.circuit.recovered', &subscriber)

      # Open circuit
      2.times do
        assert_raises(StandardError) do
          circuit.call { raise StandardError }
        end
      end

      assert circuit.open?

      # Wait for reset timeout
      sleep 1.5

      # Successful call should close circuit
      result = circuit.call { 'success' }
      assert_equal 'success', result

      # Should emit circuit.recovered event
      recovered_event = events.find { |e| e[:name] == 'star_gates.circuit.recovered' }
      assert recovered_event, 'Should emit circuit.recovered event'
      assert_equal 'closed', recovered_event[:payload][:circuit_state]
    ensure
      ActiveSupport::Notifications.unsubscribe('star_gates.circuit.recovered')
    end
  end

  # ===========================================================================
  # SELF-HEALING: Real-World Scenario
  # ===========================================================================

  def test_production_self_healing_scenario
    # Simulate production scenario:
    # 1. Feature enabled for new API
    # 2. New API starts failing
    # 3. Circuit opens, feature auto-rollbacks to canary
    # 4. Circuit half-opens after reset timeout, still failing, circuit opens again, feature disables
    # 5. Ops manually re-enables feature back to canary when API recovers

    StarGates.reset!

    StarGates.define do
      gate :new_payment_api do
        feature rollout: 100 # Full rollout
        circuit threshold: 5, within: 1.minute, reset_after: 1 # 1 second reset for test

        run { raise StandardError, 'new API down' } # Simulating failure
        fallback { 'legacy API' }
      end
    end

    gate = StarGates[:new_payment_api]
    feature = gate.feature

    # Step 1: Feature fully enabled
    feature.enable
    assert_equal 'enabled', feature.status

    # Step 2: New API fails 5 times
    5.times do
      result = gate.call
      assert_equal 'legacy API', result, 'Should use fallback'
    end

    # Step 3: Circuit opens, feature auto-rollbacks to canary
    assert gate.circuit.open?, 'Circuit should open'
    assert_equal 'canary', feature.status, 'Feature should auto-rollback to canary'

    # Step 4: Wait for circuit to half-open, then fail again to fully disable
    sleep 1.5

    # More failures in half-open → circuit re-opens → auto-rollback canary → disabled
    5.times do
      gate.call
    rescue StandardError
      nil
    end

    # Step 5: Feature should disable
    assert_equal 'disabled', feature.status, 'Feature should fully disable'

    # Step 6: Ops manually re-enables to canary when API recovers
    feature.rollout_canary
    assert_equal 'canary', feature.status
  end

  # ===========================================================================
  # SELF-HEALING: Thread Safety
  # ===========================================================================

  def test_self_healing_thread_safe
    feature = StarGates::Feature.new(rollout: 50)
    feature.enable

    circuit = StarGates::Circuit.new(
      threshold: 10,
      within: 30,
      feature: feature,
      auto_rollback: true
    )

    # Concurrent failures from multiple threads
    threads = 5.times.map do
      Thread.new do
        3.times do
          circuit.call { raise StandardError }
        rescue StandardError
          nil
        end
      end
    end

    threads.each(&:join)

    # Circuit should open
    assert circuit.open?

    # Feature should have rolled back (thread-safe state transition)
    assert_includes %w[canary disabled], feature.status
  end

  # ===========================================================================
  # SELF-HEALING: Feature Without Auto-Rollback
  # ===========================================================================

  def test_circuit_without_feature_works_normally
    # Circuit without feature should work as regular circuit breaker
    circuit = StarGates::Circuit.new(
      threshold: 2,
      within: 30,
      feature: nil # No feature attached
    )

    # Trigger failures
    2.times do
      assert_raises(StandardError) do
        circuit.call { raise StandardError }
      end
    end

    # Circuit should open normally
    assert circuit.open?

    # No auto-rollback should happen (no feature to rollback)
    # This should not raise any errors
  end

  def test_transition_history_records_auto_rollback
    feature = StarGates::Feature.new(rollout: 50)
    feature.enable

    circuit = StarGates::Circuit.new(
      threshold: 2,
      within: 30,
      feature: feature,
      auto_rollback: true
    )

    # Initial transition count
    initial_count = feature.transition_count

    # Trigger auto-rollback
    2.times do
      circuit.call { raise StandardError }
    rescue StandardError
      nil
    end

    # Should have recorded the transition
    assert feature.transition_count > initial_count, 'Should record auto-rollback transition'

    # Check transition history
    history = feature.transition_history(limit: 5)
    transitions = history[:transitions]

    # Should have enabled → canary transition
    rollback_transition = transitions.find do |t|
      t[:from_state] == :enabled && t[:to_state] == :canary
    end

    assert rollback_transition, 'Should record enabled → canary transition in history'
  end
end
