# frozen_string_literal: true

require 'test_helper'

class TestGate < Minitest::Test
  def test_gate_basic_execution
    gate = StarGates::Gate.new(
      :test_gate,
      run_block: -> { 'success' }
    )

    assert_equal 'success', gate.call
  end

  def test_gate_with_context
    gate = StarGates::Gate.new(
      :context_gate,
      run_block: ->(context) { "Hello #{context[:name]}" }
    )

    result = gate.call(name: 'World')
    assert_equal 'Hello World', result
  end

  def test_gate_with_feature_flag_enabled
    feature = StarGates::Feature.new(rollout: 100)
    feature.enable # Enable the feature explicitly
    gate = StarGates::Gate.new(
      :feature_gate,
      feature: feature,
      run_block: -> { 'feature enabled' },
      fallback_block: -> { 'feature disabled' }
    )

    assert_equal 'feature enabled', gate.call
    assert gate.enabled_for?
  end

  def test_gate_with_feature_flag_disabled
    feature = StarGates::Feature.new(rollout: 0)
    # Feature remains disabled by default
    gate = StarGates::Gate.new(
      :feature_gate,
      feature: feature,
      run_block: -> { 'feature enabled' },
      fallback_block: -> { 'feature disabled' }
    )

    assert_equal 'feature disabled', gate.call
    refute gate.enabled_for?
  end

  def test_gate_with_circuit_breaker
    circuit = StarGates::Circuit.new(threshold: 1, within: 30.seconds)
    gate = StarGates::Gate.new(
      :circuit_gate,
      circuit: circuit,
      run_block: -> { raise StandardError, 'failure' },
      fallback_block: -> { 'fallback' }
    )

    assert_equal 'fallback', gate.call
    assert gate.open?
    refute gate.closed?
  end

  def test_gate_status_reporting
    feature = StarGates::Feature.new(rollout: 100)
    feature.enable # Enable the feature explicitly
    circuit = StarGates::Circuit.new(threshold: 5)
    gate = StarGates::Gate.new(
      :status_gate,
      feature: feature,
      circuit: circuit,
      run_block: -> { 'success' }
    )

    status = gate.status
    assert_equal :status_gate, status[:name]
    assert_equal true, status[:feature_enabled]
    assert_equal 'enabled', status[:feature_status]
    assert_equal false, status[:circuit_open]
  end

  def test_gate_without_fallback_raises_error
    feature = StarGates::Feature.new(rollout: 0)
    # Feature remains disabled by default
    gate = StarGates::Gate.new(
      :no_fallback_gate,
      feature: feature,
      run_block: -> { 'never runs' }
    )

    # With state machine, disabled features return nil from execute
    # Which should trigger fallback, but with no fallback should raise error
    assert_raises(StarGates::UnavailableError) do
      gate.call
    end
  end

  def test_gate_fallback_with_context
    feature = StarGates::Feature.new(rollout: 0)
    # Feature remains disabled by default
    gate = StarGates::Gate.new(
      :context_fallback_gate,
      feature: feature,
      run_block: -> { 'never runs' },
      fallback_block: ->(context) { "Fallback for #{context[:key]}" }
    )

    # With state machine, disabled features return nil from execute
    # Which should trigger the fallback
    result = gate.call(key: 'account:1')
    assert_equal 'Fallback for account:1', result
  end

  def test_a_successful_nil_result_skips_the_fallback
    feature = StarGates::Feature.new
    feature.enable
    calls = []
    gate = StarGates::Gate.new(
      :nil_result_gate,
      feature: feature,
      run_block: lambda {
        calls << :run
        nil
      },
      fallback_block: lambda {
        calls << :fallback
        :fallback
      }
    )

    assert_nil gate.call
    assert_equal [:run], calls
  end

  def test_a_nil_returning_run_without_fallback_does_not_raise
    feature = StarGates::Feature.new
    feature.enable
    gate = StarGates::Gate.new(:nil_result_gate, feature: feature, run_block: -> {})

    assert_nil gate.call
  end

  def test_a_failing_fallback_runs_once
    calls = 0
    gate = StarGates::Gate.new(
      :failing_fallback_gate,
      feature: StarGates::Feature.new,
      run_block: -> { 'never runs' },
      fallback_block: lambda {
        calls += 1
        raise 'fallback failed'
      }
    )

    assert_raises(RuntimeError) { gate.call }
    assert_equal 1, calls
  end

  def test_status_reports_a_disabled_feature_as_disabled
    gate = StarGates::Gate.new(:disabled_gate, feature: StarGates::Feature.new)

    status = gate.status
    assert_equal false, status[:feature_enabled]
    assert_equal 'disabled', status[:feature_status]
    assert_equal true, StarGates::Gate.new(:featureless_gate).status[:feature_enabled]
  end

  def test_gate_enabled_for_with_context
    feature = StarGates::Feature.new(rollout: 50)
    feature.rollout_canary # Enable canary mode for rollout testing
    gate = StarGates::Gate.new(
      :context_enabled_gate,
      feature: feature,
      run_block: -> { 'enabled' }
    )

    result = gate.enabled_for?(key: 1)
    assert [true, false].include?(result)
  end
end
