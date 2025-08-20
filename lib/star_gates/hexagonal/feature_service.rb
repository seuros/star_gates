# frozen_string_literal: true

require_relative 'feature_repository'
require_relative '../projections/feature_projection'

module StarGates
  module Hexagonal
    class FeatureService
      def initialize(repository:, projection:, event_store:)
        @repository = repository
        @projection = projection
        @event_store = event_store
        setup_event_subscriptions
      end

      # Commands
      def create_feature(feature_id, rollout: 0, group: nil, metadata: {})
        aggregate = @repository.find_or_create(feature_id)

        unless aggregate.created?
          aggregate.create(rollout: rollout, group: group, metadata: metadata)
          @repository.save(aggregate)
        end

        aggregate
      end

      def change_feature_state(feature_id, from_state, to_state, event_name, context = {})
        aggregate = @repository.find(feature_id)
        raise FeatureNotFoundError, "Feature #{feature_id} not found" unless aggregate

        aggregate.change_state(from_state, to_state, event_name, context)
        @repository.save(aggregate)

        aggregate
      end

      def update_feature_configuration(feature_id, changes)
        aggregate = @repository.find(feature_id)
        raise FeatureNotFoundError, "Feature #{feature_id} not found" unless aggregate

        aggregate.update_configuration(changes)
        @repository.save(aggregate)

        aggregate
      end

      def record_feature_execution(feature_id, context, result, execution_time)
        aggregate = @repository.find(feature_id)
        return unless aggregate # Silently skip if feature doesn't exist

        aggregate.record_execution(context, result, execution_time)
        @repository.save(aggregate)
      end

      def record_feature_evaluation(feature_id, user_context, eligible, reason)
        aggregate = @repository.find(feature_id)
        return unless aggregate # Silently skip if feature doesn't exist

        aggregate.record_evaluation(user_context, eligible, reason)
        @repository.save(aggregate)
      end

      # Queries (delegated to projection)
      def find_feature(feature_id)
        @projection.find_feature(feature_id)
      end

      def find_features_by_state(state)
        @projection.find_features_by_state(state)
      end

      def all_features
        @projection.all_features
      end

      def feature_stats
        @projection.feature_stats
      end

      def recent_transitions(limit: 10)
        @projection.recent_transitions(limit: limit)
      end

      def feature_exists?(feature_id)
        @projection.feature_exists?(feature_id)
      end

      # Get feature aggregate for complex operations
      def get_feature_aggregate(feature_id)
        @repository.find(feature_id)
      end

      # Replay events to rebuild projections
      def rebuild_projections!
        @projection.clear! if @projection.respond_to?(:clear!)

        @event_store.replay_all do |event|
          @projection.handle_event(event)
        end
      end

      # Health check
      def healthy?
        @repository.healthy? &&
          (@event_store.respond_to?(:healthy?) ? @event_store.healthy? : true)
      end

      private

      def setup_event_subscriptions
        # Subscribe to all events to update projections
        @event_store.subscribe do |event|
          @projection.handle_event(event)
        end
      end

      class FeatureNotFoundError < StandardError; end
    end
  end
end
