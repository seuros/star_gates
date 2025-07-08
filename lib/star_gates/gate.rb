# frozen_string_literal: true

module StarGates
  class Gate
    attr_reader :name, :feature, :circuit, :run_block, :fallback_block

    def initialize(name, feature: nil, circuit: nil, run_block: nil, fallback_block: nil)
      @name = name
      @feature = feature
      @circuit = circuit
      @run_block = run_block
      @fallback_block = fallback_block
    end

    def call(context = {})
      # Use the new state-specific execute method if feature supports it
      if feature.respond_to?(:execute)
        result = if circuit
                   circuit.call { feature.execute(context) { execute_run_block(context) } }
                 else
                   feature.execute(context) { execute_run_block(context) }
                 end

        # If feature returns nil (disabled), execute fallback
        return result unless result.nil?

        execute_fallback(context)
      else
        # Fallback to old behavior for compatibility
        return execute_fallback(context) unless feature_enabled?(context)

        if circuit
          circuit.call { execute_run_block(context) }
        else
          execute_run_block(context)
        end
      end
    rescue StarGates::UnavailableError, StandardError
      execute_fallback(context)
    end

    def enabled_for?(context = {})
      feature_enabled?(context) && !circuit_open?
    end

    def open?
      circuit&.open? || false
    end

    def closed?
      !open?
    end

    def status
      {
        name: name,
        feature_enabled: feature&.enabled? || true,
        feature_status: feature.respond_to?(:status) ? feature.status : nil,
        circuit_open: circuit&.open? || false,
        last_failure: circuit&.last_failure_time
      }
    end

    private

    def feature_enabled?(context)
      return true unless feature

      feature.enabled_for?(context)
    end

    def circuit_open?
      circuit&.open? || false
    end

    def execute_run_block(context)
      return unless run_block

      if run_block.arity == 1
        run_block.call(context)
      else
        run_block.call
      end
    end

    def execute_fallback(context)
      return raise_unavailable unless fallback_block

      if fallback_block.arity == 1
        fallback_block.call(context)
      else
        fallback_block.call
      end
    end

    def raise_unavailable
      raise StarGates::UnavailableError, "Gate #{name} is unavailable and no fallback is defined"
    end
  end
end
