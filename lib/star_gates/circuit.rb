# frozen_string_literal: true

require 'chrono_machines'

module StarGates
  class Circuit
    attr_reader :breaker, :threshold, :within, :reset_after, :feature
    attr_accessor :retry_policy

    def initialize(threshold: 5, within: 30, reset_after: 60, retry_config: nil, feature: nil, auto_rollback: true)
      @threshold = threshold
      @within = parse_time(within)
      @reset_after = parse_time(reset_after)
      @feature = feature
      @auto_rollback = auto_rollback
      @breaker = create_breaker
      @retry_policy = build_retry_policy(retry_config)
    end

    def call(&block)
      # Integrate ChronoMachines for exponential backoff retries
      # This prevents the "retry death spiral" by adding jittered delays
      if @retry_policy
        ChronoMachines.retry(@retry_policy) do
          breaker.call(&block)
        end
      else
        breaker.call(&block)
      end
    rescue ChronoMachines::MaxRetriesExceededError => e
      # Re-raise the original exception after retries exhausted
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

    def last_failure_time
      # BreakerMachines stores this as last_failure_at in stats
      stats = breaker.stats
      stats.last_failure_at
    end

    def failure_count
      # BreakerMachines stores this in stats
      stats = breaker.stats
      stats.failure_count || 0
    end

    def success_count
      # BreakerMachines stores this in stats
      stats = breaker.stats
      stats.success_count || 0
    end

    def reset!
      breaker.reset
    end

    private

    def create_breaker
      # Generate a unique circuit name for this instance
      circuit_name = "star_gates_circuit_#{object_id}"

      config = {
        failure_threshold: threshold,
        failure_window: within,
        reset_timeout: reset_after,
        exceptions: [StandardError]
      }

      # Self-healing: wire circuit state to feature state
      if @feature && @auto_rollback
        config[:on_open] = -> { handle_circuit_open }
        config[:on_half_open] = -> { handle_circuit_half_open }
        config[:on_close] = -> { handle_circuit_close }
      end

      BreakerMachines::Circuit.new(circuit_name, config)
    end

    # Self-healing callbacks
    def handle_circuit_open
      return unless @feature.respond_to?(:status)

      StarGates.instrument('circuit.auto_rollback', {
                             feature_status: @feature.status,
                             circuit_state: 'open',
                             action: 'rolling_back'
                           })

      # Auto-rollback feature state when circuit opens
      case @feature.status
      when 'enabled'
        # Circuit is failing → rollback to canary
        @feature.rollout_canary if @feature.respond_to?(:rollout_canary)
      when 'canary'
        # Circuit still failing in canary → disable completely
        @feature.disable if @feature.respond_to?(:disable)
      end
    end

    def handle_circuit_half_open
      return unless @feature

      StarGates.instrument('circuit.half_open', {
                             feature_status: @feature.status,
                             circuit_state: 'half_open',
                             action: 'testing_recovery'
                           })
    end

    def handle_circuit_close
      return unless @feature

      StarGates.instrument('circuit.recovered', {
                             feature_status: @feature.status,
                             circuit_state: 'closed',
                             action: 'circuit_healthy'
                           })

      # Optionally: auto-restore to canary when circuit closes
      # (conservative: don't auto-enable to 100%, just canary)
      # Uncomment if you want auto-restoration:
      # if @feature.status == 'disabled'
      #   @feature.rollout_canary if @feature.respond_to?(:rollout_canary)
      # end
    end

    def parse_time(time)
      # Rails duration helpers can return fractional seconds.
      case time
      when Numeric then time
      when ActiveSupport::Duration then time.to_f
      else time.to_i
      end
    end

    def build_retry_policy(config)
      return nil unless config

      # Default retry policy for circuit breakers
      defaults = {
        max_attempts: 3,
        base_delay: 0.1,
        multiplier: 2,
        max_delay: 5,
        retryable_exceptions: [StandardError],
        on_retry: lambda { |exception:, attempt:, next_delay:|
          StarGates.instrument('circuit.retry', {
                                 exception: exception.class.name,
                                 attempt: attempt,
                                 next_delay: next_delay
                               })
        }
      }

      defaults.merge(config)
    end
  end
end
