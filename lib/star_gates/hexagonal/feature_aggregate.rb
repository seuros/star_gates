# frozen_string_literal: true

require_relative '../events/feature_events'

module StarGates
  module Hexagonal
    class FeatureAggregate
      attr_reader :id, :version, :uncommitted_events

      def initialize(id, events = [])
        @id = id
        @version = 0
        @uncommitted_events = []
        @state = {}

        # Replay events to rebuild state
        events.each { |event| apply_event(event, from_history: true) }
      end

      # Command: Create feature
      def create(rollout: 0, group: nil, metadata: {})
        raise ArgumentError, 'Feature already exists' if created?

        event = Events::FeatureCreated.new(
          aggregate_id: @id,
          data: {
            rollout_percentage: parse_rollout(rollout),
            group_matcher: group,
            metadata: metadata
          }
        )

        apply_event(event)
      end

      # Command: Change state
      def change_state(from_state, to_state, event_name, context = {})
        unless can_transition?(from_state, to_state, event_name)
          raise InvalidTransitionError, "Cannot transition from #{from_state} to #{to_state} via #{event_name}"
        end

        event = Events::FeatureStateChanged.new(
          aggregate_id: @id,
          from_state: from_state,
          to_state: to_state,
          event_name: event_name,
          context: context
        )

        apply_event(event)
      end

      # Command: Update configuration
      def update_configuration(changes)
        event = Events::FeatureConfigurationChanged.new(
          aggregate_id: @id,
          configuration_changes: changes
        )

        apply_event(event)
      end

      # Command: Record execution
      def record_execution(context, result, execution_time)
        event = Events::FeatureExecuted.new(
          aggregate_id: @id,
          context: context,
          result: result,
          execution_time: execution_time
        )

        apply_event(event)
      end

      # Command: Record evaluation
      def record_evaluation(user_context, eligible, reason)
        event = Events::FeatureEvaluated.new(
          aggregate_id: @id,
          user_context: user_context,
          eligible: eligible,
          reason: reason
        )

        apply_event(event)
      end

      # Queries
      def created?
        @state[:created] || false
      end

      def current_state
        @state[:current_state] || :disabled
      end

      def rollout_percentage
        @state[:rollout_percentage] || 0
      end

      def group_matcher
        @state[:group_matcher]
      end

      def configuration
        @state[:configuration] || {}
      end

      def transition_history
        @state[:transitions] || []
      end

      def execution_history
        @state[:executions] || []
      end

      def evaluation_history
        @state[:evaluations] || []
      end

      # Mark events as committed
      def mark_events_as_committed
        @uncommitted_events.clear
      end

      # Get snapshot for rebuilding
      def to_snapshot
        {
          id: @id,
          version: @version,
          state: @state.dup
        }
      end

      # Load from snapshot
      def self.from_snapshot(snapshot, events_since_snapshot = [])
        aggregate = allocate
        aggregate.instance_variable_set(:@id, snapshot[:id])
        aggregate.instance_variable_set(:@version, snapshot[:version])
        aggregate.instance_variable_set(:@state, snapshot[:state].dup)
        aggregate.instance_variable_set(:@uncommitted_events, [])

        # Apply events since snapshot
        events_since_snapshot.each { |event| aggregate.apply_event(event, from_history: true) }

        aggregate
      end

      private

      def apply_event(event, from_history: false)
        case event
        when Events::FeatureCreated
          apply_feature_created(event)
        when Events::FeatureStateChanged
          apply_state_changed(event)
        when Events::FeatureConfigurationChanged
          apply_configuration_changed(event)
        when Events::FeatureExecuted
          apply_execution_recorded(event)
        when Events::FeatureEvaluated
          apply_evaluation_recorded(event)
        end

        @version += 1 if from_history
        @uncommitted_events << event unless from_history
      end

      def apply_feature_created(event)
        @state[:created] = true
        @state[:current_state] = :disabled
        @state[:rollout_percentage] = event.data[:rollout_percentage]
        @state[:group_matcher] = event.data[:group_matcher]
        @state[:metadata] = event.data[:metadata]
        @state[:transitions] = []
        @state[:executions] = []
        @state[:evaluations] = []
        @state[:configuration] = {}
      end

      def apply_state_changed(event)
        @state[:current_state] = event.to_state
        @state[:transitions] ||= []
        @state[:transitions] << {
          from_state: event.from_state,
          to_state: event.to_state,
          event_name: event.event_name,
          context: event.context,
          occurred_at: event.occurred_at
        }

        # Keep only last 50 transitions for memory efficiency
        @state[:transitions] = @state[:transitions].last(50) if @state[:transitions].size > 50
      end

      def apply_configuration_changed(event)
        @state[:configuration] ||= {}
        @state[:configuration].merge!(event.configuration_changes)
      end

      def apply_execution_recorded(event)
        @state[:executions] ||= []
        @state[:executions] << {
          context: event.context,
          result: event.result,
          execution_time: event.execution_time,
          occurred_at: event.occurred_at
        }

        # Keep only last 100 executions
        @state[:executions] = @state[:executions].last(100) if @state[:executions].size > 100
      end

      def apply_evaluation_recorded(event)
        @state[:evaluations] ||= []
        @state[:evaluations] << {
          user_context: event.user_context,
          eligible: event.eligible,
          reason: event.reason,
          occurred_at: event.occurred_at
        }

        # Keep only last 100 evaluations
        @state[:evaluations] = @state[:evaluations].last(100) if @state[:evaluations].size > 100
      end

      def can_transition?(from_state, to_state, event_name)
        # Define valid transitions
        valid_transitions = {
          disabled: { rollout_canary: :canary, enable: :enabled },
          canary: { enable: :enabled, disable: :disabled },
          enabled: { disable: :disabled, rollout_canary: :canary }
        }

        allowed_transitions = valid_transitions[from_state.to_sym] || {}
        allowed_transitions[event_name.to_sym] == to_state.to_sym
      end

      def parse_rollout(rollout)
        case rollout
        when Numeric, String
          rollout.to_i
        else
          0
        end
      end

      class InvalidTransitionError < StandardError; end
    end
  end
end
