# frozen_string_literal: true

module StarGates
  # A named entry point: a feature decides whether the primary path runs, a
  # circuit guards it, and the fallback answers when it does not.
  #
  # The fallback runs when the primary is unavailable: the feature is off for
  # the context, the circuit refuses, the primary raises, or the time budget
  # runs out. Without a fallback, `call` raises UnavailableError whose
  # `refusal` says which, with the primary's exception as its `cause`.
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
      error = nil
      refusal, result = begin
        execute_primary(context)
      rescue StandardError => e
        error = e
        [refusal_for(e), nil]
      end
      return result unless refusal

      execute_fallback(context, refusal, error)
    end

    def enabled_for?(context = {})
      feature_enabled?(context) && !open?
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
        circuit_open: open?,
        last_failure_at: circuit&.last_failure_at
      }
    end

    private

    # [nil, result] when the primary ran, [refusal, nil] when it did not.
    def execute_primary(context)
      return execute_feature(context) if feature.respond_to?(:execute)
      return [:ineligible, nil] unless feature_enabled?(context)

      [nil, with_circuit { execute_run_block(context) }]
    end

    def execute_feature(context)
      executed = false
      result = with_circuit do
        feature.execute(context) do
          executed = true
          execute_run_block(context)
        end
      end

      executed ? [nil, result] : [:ineligible, nil]
    end

    def refusal_for(error)
      case error
      when BreakerMachines::CircuitRefusedError then error.refusal
      when UnavailableError then error.refusal
      else :failed
      end
    end

    def with_circuit(&block)
      circuit ? circuit.call(&block) : block.call
    end

    def feature_enabled?(context)
      return true unless feature

      feature.enabled_for?(context)
    end

    def execute_run_block(context)
      return unless run_block

      run_block.arity == 1 ? run_block.call(context) : run_block.call
    end

    def execute_fallback(context, refusal, error)
      unless fallback_block
        raise UnavailableError.new(name, refusal, "Gate #{name} is unavailable (#{refusal}) and has no fallback"),
              cause: error
      end

      fallback_block.arity == 1 ? fallback_block.call(context) : fallback_block.call
    end
  end
end
