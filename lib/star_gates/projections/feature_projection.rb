# frozen_string_literal: true

module StarGates
  module Projections
    class FeatureProjection
      def initialize(adapter)
        @adapter = adapter
        @mutex = Mutex.new
      end

      # Handle events to build read model
      def handle_event(event)
        case event
        when Events::FeatureCreated
          handle_feature_created(event)
        when Events::FeatureStateChanged
          handle_state_changed(event)
        when Events::FeatureConfigurationChanged
          handle_configuration_changed(event)
        when Events::FeatureExecuted
          handle_execution_recorded(event)
        when Events::FeatureEvaluated
          handle_evaluation_recorded(event)
        end
      end

      # Query methods
      def find_feature(feature_id)
        @adapter.fetch("feature:#{feature_id}")
      end

      def find_features_by_state(state)
        state_key = "features_by_state:#{state}"
        feature_ids = @adapter.fetch(state_key) || []
        feature_ids.map { |id| find_feature(id) }.compact
      end

      def all_features
        feature_ids = @adapter.fetch('all_features') || []
        feature_ids.map { |id| find_feature(id) }.compact
      end

      def feature_stats
        {
          total_features: all_features.size,
          by_state: features_by_state_count,
          recent_transitions: recent_transitions_count,
          total_executions: total_executions_count
        }
      end

      def recent_transitions(limit: 10)
        transitions = @adapter.fetch('recent_transitions') || []
        transitions.last(limit).reverse
      end

      def feature_exists?(feature_id)
        @adapter.exists?("feature:#{feature_id}")
      end

      # Clear projection (for testing)
      def clear!
        return unless @adapter.respond_to?(:clear!)

        @adapter.clear!
      end

      private

      def handle_feature_created(event)
        @mutex.synchronize do
          feature_data = {
            id: event.aggregate_id,
            state: :disabled,
            rollout_percentage: event.data[:rollout_percentage],
            group_matcher: event.data[:group_matcher],
            metadata: event.data[:metadata],
            created_at: event.occurred_at,
            updated_at: event.occurred_at,
            transition_count: 0,
            execution_count: 0,
            evaluation_count: 0
          }

          # Store feature
          @adapter.store("feature:#{event.aggregate_id}", feature_data)

          # Update indexes
          update_all_features_index(event.aggregate_id, :add)
          update_state_index(event.aggregate_id, :disabled, :add)
        end
      end

      def handle_state_changed(event)
        @mutex.synchronize do
          feature_data = @adapter.fetch("feature:#{event.aggregate_id}")
          return unless feature_data

          old_state = feature_data[:state]
          new_state = event.to_state

          # Update feature data
          feature_data[:state] = new_state
          feature_data[:updated_at] = event.occurred_at
          feature_data[:transition_count] += 1

          @adapter.store("feature:#{event.aggregate_id}", feature_data)

          # Update state indexes
          update_state_index(event.aggregate_id, old_state, :remove)
          update_state_index(event.aggregate_id, new_state, :add)

          # Update recent transitions
          update_recent_transitions(event)
        end
      end

      def handle_configuration_changed(event)
        @mutex.synchronize do
          feature_data = @adapter.fetch("feature:#{event.aggregate_id}")
          return unless feature_data

          feature_data[:updated_at] = event.occurred_at
          @adapter.store("feature:#{event.aggregate_id}", feature_data)
        end
      end

      def handle_execution_recorded(event)
        @mutex.synchronize do
          feature_data = @adapter.fetch("feature:#{event.aggregate_id}")
          return unless feature_data

          feature_data[:execution_count] += 1
          feature_data[:updated_at] = event.occurred_at
          @adapter.store("feature:#{event.aggregate_id}", feature_data)
        end
      end

      def handle_evaluation_recorded(event)
        @mutex.synchronize do
          feature_data = @adapter.fetch("feature:#{event.aggregate_id}")
          return unless feature_data

          feature_data[:evaluation_count] += 1
          feature_data[:updated_at] = event.occurred_at
          @adapter.store("feature:#{event.aggregate_id}", feature_data)
        end
      end

      def update_all_features_index(feature_id, operation)
        key = 'all_features'
        feature_ids = @adapter.fetch(key) || []

        case operation
        when :add
          feature_ids << feature_id unless feature_ids.include?(feature_id)
        when :remove
          feature_ids.delete(feature_id)
        end

        @adapter.store(key, feature_ids)
      end

      def update_state_index(feature_id, state, operation)
        key = "features_by_state:#{state}"
        feature_ids = @adapter.fetch(key) || []

        case operation
        when :add
          feature_ids << feature_id unless feature_ids.include?(feature_id)
        when :remove
          feature_ids.delete(feature_id)
        end

        @adapter.store(key, feature_ids)
      end

      def update_recent_transitions(event)
        transitions = @adapter.fetch('recent_transitions') || []

        transition_data = {
          feature_id: event.aggregate_id,
          from_state: event.from_state,
          to_state: event.to_state,
          event_name: event.event_name,
          context: event.context,
          occurred_at: event.occurred_at
        }

        transitions << transition_data

        # Keep only last 100 transitions
        transitions = transitions.last(100) if transitions.size > 100

        @adapter.store('recent_transitions', transitions)
      end

      def features_by_state_count
        states = %i[disabled canary enabled]
        counts = {}

        states.each do |state|
          feature_ids = @adapter.fetch("features_by_state:#{state}") || []
          counts[state] = feature_ids.size
        end

        counts
      end

      def recent_transitions_count(days: 7)
        transitions = @adapter.fetch('recent_transitions') || []
        cutoff = Time.now - (days * 24 * 60 * 60)

        transitions.count do |transition|
          Time.parse(transition[:occurred_at].to_s) > cutoff
        end
      end

      def total_executions_count
        all_features.sum { |feature| feature[:execution_count] || 0 }
      end
    end
  end
end
