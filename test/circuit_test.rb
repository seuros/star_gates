# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class TestCircuit < Minitest::Test
  def test_circuit_closed_by_default
    circuit = StarGates::Circuit.new

    assert circuit.closed?
    refute circuit.open?
  end

  def test_circuit_opens_on_failures
    circuit = StarGates::Circuit.new(threshold: 2, within: 30.seconds)

    assert circuit.closed?

    assert_raises(StandardError) do
      circuit.call { raise StandardError, 'failure 1' }
    end

    assert_raises(StandardError) do
      circuit.call { raise StandardError, 'failure 2' }
    end

    assert circuit.open?
  end

  def test_circuit_successful_calls
    circuit = StarGates::Circuit.new

    result1 = circuit.call { 'success 1' }
    result2 = circuit.call { 'success 2' }

    assert_equal 'success 1', result1
    assert_equal 'success 2', result2
    assert circuit.closed?
  end

  def test_circuit_time_parsing
    circuit = StarGates::Circuit.new(
      threshold: 3,
      within: 2.minutes,
      reset_after: 5.minutes
    )

    assert circuit.closed?
  end

  def test_circuit_string_time_parsing
    circuit = StarGates::Circuit.new(
      threshold: 3,
      within: '2 minutes',
      reset_after: '5 minutes'
    )

    assert circuit.closed?
  end

  def test_circuit_preserves_fractional_durations
    circuit = StarGates::Circuit.new(within: 0.25.seconds, reset_after: 0.5.seconds)

    assert_in_delta 0.25, circuit.within
    assert_in_delta 0.5, circuit.reset_after
    assert_in_delta 0.25, circuit.breaker.config[:failure_window]
    assert_in_delta 0.5, circuit.breaker.config[:reset_timeout]
  end

  def test_circuit_preserves_fractional_numeric_seconds
    circuit = StarGates::Circuit.new(within: 0.25, reset_after: 0.5)

    assert_in_delta 0.25, circuit.within
    assert_in_delta 0.5, circuit.reset_after
  end

  def test_fractional_cooldown_blocks_calls_after_failure
    now = 1000.0
    BreakerMachines.stub(:monotonic_time, -> { now }) do
      circuit = StarGates::Circuit.new(threshold: 1, reset_after: 0.5.seconds)

      assert_raises(StandardError) { circuit.call { raise 'failure' } }
      assert circuit.open?

      now += 0.25
      called = false
      assert_raises(BreakerMachines::CircuitOpenError) do
        circuit.call { called = true }
      end
      refute called
      assert circuit.open?

      now += 0.5
      result = circuit.call { 'recovered' }
      assert_equal 'recovered', result
    end
  end

  def test_circuit_reset
    circuit = StarGates::Circuit.new(threshold: 1, within: 30.seconds)

    assert_raises(StandardError) do
      circuit.call { raise StandardError, 'failure' }
    end

    assert circuit.open?

    circuit.reset!
    assert circuit.closed?
  end

  def test_numeric_time_extensions
    assert_equal 30, 30.seconds
    assert_equal 60, 1.minute
    assert_equal 120, 2.minutes
    assert_equal 3600, 1.hour
    assert_equal 7200, 2.hours
  end
end
