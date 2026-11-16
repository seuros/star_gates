# frozen_string_literal: true

require_relative 'feature_repository'
require_relative '../projections/feature_projection'

module StarGates
  module Hexagonal
    # Commands answer the aggregate, or a refusal symbol and change nothing:
    # :not_found, the aggregate's own refusals (:invalid_transition,
    # :stale_state) and the store's (:version_conflict).
    class FeatureService
      def initialize(repository:, projection:, event_store:)
        @repository = repository
        @projection = projection
        @event_store = event_store
        setup_event_subscriptions
      end

      # The feature, created unless it exists. A creation that loses a race
      # answers the winner's feature.
      def create_feature(feature_id, rollout: 0, group: nil, metadata: {})
        aggregate = @repository.find_or_create(feature_id)
        return aggregate if aggregate.created?

        aggregate.create(rollout: rollout, group: group, metadata: metadata)
        saved = @repository.save(aggregate, expected_version: aggregate.version)
        saved.is_a?(Symbol) ? @repository.find(feature_id) : aggregate
      end

      def change_feature_state(feature_id, from_state, to_state, event_name, context = {})
        command(feature_id) { |aggregate| aggregate.change_state(from_state, to_state, event_name, context) }
      end

      def update_feature_configuration(feature_id, changes)
        command(feature_id) { |aggregate| aggregate.update_configuration(changes) }
      end

      # `execution_time` in Integer nanoseconds.
      def record_feature_execution(feature_id, context, result, execution_time)
        command(feature_id) { |aggregate| aggregate.record_execution(context, result, execution_time) }
      end

      def record_feature_evaluation(feature_id, context, eligible, reason)
        command(feature_id) { |aggregate| aggregate.record_evaluation(context, eligible, reason) }
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

      def transition_count
        @projection.transition_count
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

      # Loads the aggregate, applies the block's command and saves it under
      # the version it was loaded at, so a concurrent writer is refused.
      def command(feature_id)
        aggregate = @repository.find(feature_id)
        return :not_found unless aggregate

        outcome = yield aggregate
        return outcome if outcome.is_a?(Symbol)

        saved = @repository.save(aggregate, expected_version: aggregate.version)
        saved.is_a?(Symbol) ? saved : aggregate
      end

      def setup_event_subscriptions
        # Subscribe to all events to update projections
        @event_store.subscribe do |event|
          @projection.handle_event(event)
        end
      end
    end
  end
end
