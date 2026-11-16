# frozen_string_literal: true

require_relative '../events/feature_events'

module StarGates
  module Hexagonal
    # A feature's event-sourced state. Each command answers the event it
    # recorded, or a refusal symbol and changes nothing: :already_created,
    # :invalid_transition (no such event between those states), :stale_state
    # (the feature is not in `from_state`).
    #
    # States and event names are Symbols. A String (or any other type) is a
    # TypeError raised before anything changes: the aggregate never stores a
    # name it would later fail to match. Wire adapters convert at their own
    # boundary (JsonrpcRailsAdapter does).
    #
    # `version` counts the events the store holds: replayed and saved ones.
    class FeatureAggregate
      TRANSITIONS = {
        disabled: { rollout_canary: :canary, enable: :enabled },
        canary: { enable: :enabled, disable: :disabled },
        enabled: { disable: :disabled, rollout_canary: :canary }
      }.freeze
      TRANSITIONS_KEPT = 50
      RECORDS_KEPT = 100

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
        Rollout.validated(rollout)
        return :already_created if created?

        event = Events::FeatureCreated.new(
          aggregate_id: @id,
          data: {
            rollout_percentage: rollout,
            group_matcher: group,
            metadata: metadata
          }
        )

        apply_event(event)
      end

      # Command: Change state
      def change_state(from_state, to_state, event_name, context = {})
        { from_state:, to_state:, event_name: }.each { |name, value| symbol!(name, value) }
        return :invalid_transition unless TRANSITIONS.dig(from_state, event_name) == to_state
        return :stale_state unless from_state == current_state

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
      def record_evaluation(context, eligible, reason)
        event = Events::FeatureEvaluated.new(
          aggregate_id: @id,
          context: context,
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

      # The store now holds the uncommitted events.
      def mark_events_as_committed
        @version += @uncommitted_events.size
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
        new(snapshot[:id]).tap { |aggregate| aggregate.__send__(:restore, snapshot, events_since_snapshot) }
      end

      private

      def restore(snapshot, events)
        @version = snapshot[:version]
        @state = snapshot[:state].dup
        events.each { |event| apply_event(event, from_history: true) }
      end

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
        event
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
        @state[:transitions] = append(:transitions, TRANSITIONS_KEPT, {
          from_state: event.from_state,
          to_state: event.to_state,
          event_name: event.event_name,
          context: event.context,
          occurred_at: event.occurred_at
        })
      end

      def apply_configuration_changed(event)
        @state[:configuration] = configuration.merge(event.configuration_changes)
      end

      def apply_execution_recorded(event)
        @state[:executions] = append(:executions, RECORDS_KEPT, {
          context: event.context,
          result: event.result,
          execution_time: event.execution_time,
          occurred_at: event.occurred_at
        })
      end

      def apply_evaluation_recorded(event)
        @state[:evaluations] = append(:evaluations, RECORDS_KEPT, {
          context: event.context,
          eligible: event.eligible,
          reason: event.reason,
          occurred_at: event.occurred_at
        })
      end

      # A new list, so a snapshot taken earlier keeps its own.
      def append(key, kept, record)
        [*@state[key], record].last(kept)
      end

      def symbol!(name, value)
        return if value.is_a?(Symbol)

        raise TypeError, "#{name} must be a Symbol, got #{value.inspect}"
      end
    end
  end
end
