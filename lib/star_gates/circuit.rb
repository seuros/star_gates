# frozen_string_literal: true

require 'chrono_machines'

module StarGates
  # A breaker_machines circuit with optional chrono_machines retries, wired
  # to a feature so an opening circuit rolls the feature back.
  #
  # `policy` (a BreakerMachines::Policy, spans in Integer nanoseconds) and
  # `retry_policy` (a RetryPolicy or nil) are positional, as the cores take
  # them. The keywords belong to this runtime and have no core counterpart:
  #
  # - `feature:` the feature to roll back when the circuit opens.
  # - `auto_rollback:` whether to roll it back (true).
  #
  # A refused call (the circuit is open, busy or full) is never retried: the
  # refusal is the circuit's answer, and waiting out a cooldown inside a
  # request helps nobody. Exhausted retries re-raise the last exception.
  class Circuit
    HALT_ON_REFUSAL = lambda do |exception:, attempt:|
      _ = attempt
      :halt if exception.is_a?(BreakerMachines::CircuitRefusedError)
    end
    private_constant :HALT_ON_REFUSAL

    attr_reader :breaker, :policy, :retry_policy, :feature

    def initialize(policy, retry_policy = nil, feature: nil, auto_rollback: true)
      unless retry_policy.nil? || retry_policy.instance_of?(RetryPolicy)
        raise TypeError, "retry_policy must be a StarGates::RetryPolicy or nil, got #{retry_policy.inspect}"
      end
      unless [true, false].include?(auto_rollback)
        raise TypeError, "auto_rollback must be true or false, got #{auto_rollback.inspect}"
      end

      @policy = policy
      @retry_policy = retry_policy
      @feature = feature
      @auto_rollback = auto_rollback
      @breaker = BreakerMachines::Circuit.new("star_gates_circuit_#{object_id}", policy,
                                              exceptions: [StandardError], **rollback_hooks)
      freeze
    end

    def call(&block)
      return breaker.call(&block) unless retry_policy

      ChronoMachines.retry(retry_policy.strategy, retry_policy.max_attempts,
                           delay_from: HALT_ON_REFUSAL, on_retry: method(:instrument_retry)) do
        breaker.call(&block)
      end
    rescue ChronoMachines::MaxRetriesExceededError => e
      raise e.original_exception
    end

    def open?
      breaker.open?
    end

    def closed?
      breaker.closed?
    end

    def half_open?
      breaker.half_open?
    end

    # When the last failure was recorded, Integer nanoseconds on the
    # breaker's clock, or nil.
    def last_failure_at
      breaker.stats.last_failure_at
    end

    def failure_count
      breaker.stats.failure_count
    end

    def success_count
      breaker.stats.success_count
    end

    def to_h
      { state: breaker.status_name, failure_count: failure_count, success_count: success_count,
        last_failure_at: last_failure_at }
    end

    # Closes the circuit and clears its failure window.
    def reset
      breaker.reset
      self
    end

    private

    def rollback_hooks
      return {} unless @feature && @auto_rollback

      {
        on_open: -> { handle_circuit_open },
        on_half_open: -> { handle_circuit_half_open },
        on_close: -> { handle_circuit_close }
      }
    end

    def instrument_retry(exception:, attempt:, next_delay:)
      StarGates.instrument('circuit.retry', exception: exception.class.name, attempt: attempt, next_delay: next_delay)
    end

    def feature_status
      @feature.status if @feature.respond_to?(:status)
    end

    # Enabled rolls back to canary; canary rolls back to disabled.
    def handle_circuit_open
      return unless @feature.respond_to?(:status)

      StarGates.instrument('circuit.auto_rollback', feature_status: feature_status, circuit_state: 'open',
                                                    action: 'rolling_back')
      case feature_status
      when 'enabled' then @feature.rollout_canary if @feature.respond_to?(:rollout_canary)
      when 'canary' then @feature.disable if @feature.respond_to?(:disable)
      end
    end

    def handle_circuit_half_open
      StarGates.instrument('circuit.half_open', feature_status: feature_status, circuit_state: 'half_open',
                                                action: 'testing_recovery')
    end

    # Recovery does not re-enable the feature: an operator decides that.
    def handle_circuit_close
      StarGates.instrument('circuit.recovered', feature_status: feature_status, circuit_state: 'closed',
                                                action: 'circuit_healthy')
    end
  end
end
