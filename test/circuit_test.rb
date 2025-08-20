# frozen_string_literal: true

require 'test_helper'

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
