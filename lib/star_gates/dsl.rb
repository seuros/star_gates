# frozen_string_literal: true

module StarGates
  module DSL
    class GateBuilder
      attr_reader :name, :feature_config, :circuit_config, :run_block, :fallback_block

      def initialize(name)
        @name = name
        @feature_config = {}
        @circuit_config = nil
        @run_block = nil
        @fallback_block = nil
      end

      def feature(rollout: 0, group: nil)
        @feature_config = { rollout: rollout, group: group }
      end

      # A BreakerMachines::Policy and an optional RetryPolicy, as
      # Circuit.new takes them; the circuit is wired to this gate's feature.
      def circuit(policy, retry_policy = nil)
        @circuit_config = [policy, retry_policy]
      end

      def run(&block)
        @run_block = block
      end

      def fallback(&block)
        @fallback_block = block
      end

      def build
        feature_instance = build_feature if feature_config.any?
        circuit_instance = build_circuit(feature_instance) if circuit_config

        StarGates::Gate.new(
          name,
          feature: feature_instance,
          circuit: circuit_instance,
          run_block: run_block,
          fallback_block: fallback_block
        )
      end

      private

      def build_feature
        StarGates::Feature.new(**feature_config)
      end

      def build_circuit(feature)
        # Wire circuit to feature for self-healing behavior
        StarGates::Circuit.new(*circuit_config, feature: feature)
      end
    end

    class DefineContext
      def initialize(registry)
        @registry = registry
      end

      def gate(name, &)
        builder = GateBuilder.new(name)
        builder.instance_eval(&) if block_given?
        gate_instance = builder.build
        @registry.register(name, gate_instance)
        gate_instance
      end
    end
  end
end
