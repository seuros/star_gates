# frozen_string_literal: true

require 'test_helper'
require 'minitest/mock'

class TestCircuit < Minitest::Test
  def test_circuit_closed_by_default
    circuit = StarGates::Circuit.new(breaker_policy)

    assert circuit.closed?
    refute circuit.open?
    refute circuit.half_open?
  end

  def test_policy_and_retry_policy_are_kept
    policy = breaker_policy(3)
    retry_policy = quick_retry(2)
    circuit = StarGates::Circuit.new(policy, retry_policy)

    assert_same policy, circuit.policy
    assert_same retry_policy, circuit.retry_policy
    assert_equal policy, circuit.breaker.policy
    assert_nil circuit.feature
    assert_predicate circuit, :frozen?
  end

  def test_policy_must_be_a_breaker_policy
    assert_raises(TypeError) { StarGates::Circuit.new({ failure_threshold: 5 }) }
  end

  def test_retry_policy_must_be_a_retry_policy
    assert_raises(TypeError) { StarGates::Circuit.new(breaker_policy, { max_attempts: 3 }) }
  end

  def test_auto_rollback_must_be_a_boolean
    assert_raises(TypeError) { StarGates::Circuit.new(breaker_policy, auto_rollback: nil) }
  end

  def test_circuit_opens_on_failures
    circuit = StarGates::Circuit.new(breaker_policy(2))

    2.times { assert_raises(StandardError) { circuit.call { raise StandardError, 'failure' } } }

    assert circuit.open?
    assert_equal 2, circuit.failure_count
  end

  def test_circuit_successful_calls
    circuit = StarGates::Circuit.new(breaker_policy)

    assert_equal 'success 1', circuit.call { 'success 1' }
    assert_equal 'success 2', circuit.call { 'success 2' }
    assert circuit.closed?
    assert_equal 2, circuit.success_count
  end

  def test_last_failure_at_is_integer_nanoseconds_on_the_breaker_clock
    now = 5_000_000_000
    BreakerMachines.stub(:monotonic_time, -> { now }) do
      circuit = StarGates::Circuit.new(breaker_policy)
      assert_nil circuit.last_failure_at

      assert_raises(RuntimeError) { circuit.call { raise 'failure' } }
      assert_equal 5_000_000_000, circuit.last_failure_at
    end
  end

  def test_cooldown_in_nanoseconds_blocks_calls_after_failure
    now = 1_000_000_000_000
    BreakerMachines.stub(:monotonic_time, -> { now }) do
      circuit = StarGates::Circuit.new(breaker_policy(1, reset_after: 500_000_000))

      assert_raises(StandardError) { circuit.call { raise 'failure' } }
      assert circuit.open?

      now += 250_000_000
      called = false
      error = assert_raises(BreakerMachines::CircuitOpenError) { circuit.call { called = true } }
      refute called
      assert_equal :open, error.refusal

      now += 500_000_000
      assert_equal 'recovered', circuit.call { 'recovered' }
      assert circuit.closed?
    end
  end

  def test_circuit_reset
    circuit = StarGates::Circuit.new(breaker_policy(1))

    assert_raises(StandardError) { circuit.call { raise StandardError, 'failure' } }
    assert circuit.open?

    assert_same circuit, circuit.reset
    assert circuit.closed?
    assert_equal 0, circuit.failure_count
  end

  def test_to_h
    circuit = StarGates::Circuit.new(breaker_policy)
    circuit.call { :ok }

    assert_equal({ state: :closed, failure_count: 0, success_count: 1, last_failure_at: nil }, circuit.to_h)
  end

  def test_retries_until_success
    calls = 0
    circuit = StarGates::Circuit.new(breaker_policy, quick_retry(3))

    result = circuit.call do
      calls += 1
      raise 'transient' if calls < 3

      :ok
    end

    assert_equal :ok, result
    assert_equal 3, calls
  end

  def test_exhausted_retries_reraise_the_last_exception
    calls = 0
    circuit = StarGates::Circuit.new(breaker_policy, quick_retry(2))

    error = assert_raises(RuntimeError) do
      circuit.call do
        calls += 1
        raise "failure #{calls}"
      end
    end
    assert_equal 'failure 2', error.message
    assert_equal 2, calls
  end

  # Bug: every StandardError was retryable, the circuit's own refusal
  # included, so an open circuit slept through each backoff and retried a
  # call it would only refuse again.
  def test_a_refused_call_is_not_retried
    retries = []
    calls = 0
    circuit = StarGates::Circuit.new(breaker_policy(1), quick_retry(5))

    ActiveSupport::Notifications.subscribed(->(*args) { retries << args.last }, 'star_gates.circuit.retry') do
      # The first failure opens the circuit; the retry it earns is refused,
      # and that refusal is the answer.
      error = assert_raises(BreakerMachines::CircuitOpenError) do
        circuit.call do
          calls += 1
          raise 'down'
        end
      end
      assert_equal :open, error.refusal
      assert_raises(BreakerMachines::CircuitOpenError) { circuit.call { calls += 1 } }
    end
    assert_equal 1, calls
    assert_equal [{ exception: 'RuntimeError', attempt: 1, next_delay: 1_000 }], retries
  end

  def test_retry_instrumentation_reports_nanoseconds
    retries = []
    calls = 0
    circuit = StarGates::Circuit.new(breaker_policy, quick_retry(2))

    ActiveSupport::Notifications.subscribed(->(*args) { retries << args.last }, 'star_gates.circuit.retry') do
      circuit.call do
        calls += 1
        raise 'transient' if calls == 1

        :ok
      end
    end
    assert_equal [{ exception: 'RuntimeError', attempt: 1, next_delay: 1_000 }], retries
  end
end
