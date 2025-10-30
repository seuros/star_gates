# frozen_string_literal: true

module StarGates
  class Circuit
    attr_reader :breaker, :threshold, :within, :reset_after

    def initialize(threshold: 5, within: 30, reset_after: 60)
      @threshold = threshold
      @within = parse_time(within)
      @reset_after = parse_time(reset_after)
      @breaker = create_breaker
    end

    def call(&)
      breaker.call(&)
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

      BreakerMachines::Circuit.new(circuit_name, {
        failure_threshold: threshold,
        failure_window: within,
        reset_timeout: reset_after,
        exceptions: [StandardError]
      })
    end

    def parse_time(time)
      case time
      when Numeric
        time
      when String
        parse_time_string(time)
      else
        time.respond_to?(:to_i) ? time.to_i : 30
      end
    end

    def parse_time_string(time_str)
      case time_str
      when /(\d+)\.?seconds?/
        ::Regexp.last_match(1).to_i
      when /(\d+)\.?minutes?/
        ::Regexp.last_match(1).to_i * 60
      when /(\d+)\.?hours?/
        ::Regexp.last_match(1).to_i * 3600
      else
        time_str.to_i
      end
    end
  end
end
