# frozen_string_literal: true

require_relative 'base_event'

module StarGates
  module Events
    # Feature lifecycle events
    class FeatureCreated < BaseEvent; end

    class FeatureStateChanged < BaseEvent
      def initialize(aggregate_id:, from_state:, to_state:, event_name:, context: {}, **opts)
        super(
          aggregate_id: aggregate_id,
          data: {
            from_state: from_state,
            to_state: to_state,
            event_name: event_name,
            context: context
          },
          **opts
        )
      end

      def from_state = data[:from_state]
      def to_state = data[:to_state]
      def event_name = data[:event_name]
      def context = data[:context]
    end

    class FeatureConfigurationChanged < BaseEvent
      def initialize(aggregate_id:, configuration_changes:, **opts)
        super(
          aggregate_id: aggregate_id,
          data: { configuration_changes: configuration_changes },
          **opts
        )
      end

      def configuration_changes = data[:configuration_changes]
    end

    class FeatureExecuted < BaseEvent
      def initialize(aggregate_id:, context:, result:, execution_time:, **opts)
        super(
          aggregate_id: aggregate_id,
          data: {
            context: context,
            result: result,
            execution_time: execution_time
          },
          **opts
        )
      end

      def context = data[:context]
      def result = data[:result]
      def execution_time = data[:execution_time]
    end

    class FeatureEvaluated < BaseEvent
      def initialize(aggregate_id:, context:, eligible:, reason:, **opts)
        super(
          aggregate_id: aggregate_id,
          data: {
            context: context,
            eligible: eligible,
            reason: reason
          },
          **opts
        )
      end

      def context = data[:context]
      def eligible = data[:eligible]
      def reason = data[:reason]
    end

    # System-level events
    class GateRegistered < BaseEvent
      def initialize(aggregate_id:, gate_name:, feature_class:, **opts)
        super(
          aggregate_id: aggregate_id,
          data: {
            gate_name: gate_name,
            feature_class: feature_class
          },
          **opts
        )
      end

      def gate_name = data[:gate_name]
      def feature_class = data[:feature_class]
    end

    class SystemReset < BaseEvent; end
  end
end
