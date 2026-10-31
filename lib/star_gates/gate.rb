# frozen_string_literal: true

module StarGates
  class Gate
    UNAVAILABLE = Object.new
    private_constant :UNAVAILABLE

    attr_reader :name, :feature, :circuit, :run_block, :fallback_block

    def initialize(name, feature: nil, circuit: nil, run_block: nil, fallback_block: nil)
      @name = name
      @feature = feature
      @circuit = circuit
      @run_block = run_block
      @fallback_block = fallback_block
    end

    def call(context = {})
      result = begin
        execute_primary(context)
      rescue StandardError
        UNAVAILABLE
      end

      return execute_fallback(context) if result.equal?(UNAVAILABLE)

      result
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
        feature_enabled: feature.nil? || feature.enabled?,
        feature_status: feature.respond_to?(:status) ? feature.status : nil,
        circuit_open: circuit&.open? || false,
        last_failure: circuit&.last_failure_time
      }
    end

    private

    def execute_primary(context)
      return execute_feature(context) if feature.respond_to?(:execute)
      return UNAVAILABLE unless feature_enabled?(context)

      with_circuit { execute_run_block(context) }
    end

    def execute_feature(context)
      executed = false
      result = with_circuit do
        feature.execute(context) do
          executed = true
          execute_run_block(context)
        end
      end

      executed ? result : UNAVAILABLE
    end

    def with_circuit(&block)
      circuit ? circuit.call(&block) : block.call
    end

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
