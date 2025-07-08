# frozen_string_literal: true

require_relative 'feature_aggregate'

module StarGates
  module Hexagonal
    class FeatureRepository
      def initialize(event_store)
        @event_store = event_store
      end

      # Load feature aggregate from event store
      def find(feature_id)
        events = @event_store.get_events(feature_id)
        return nil if events.empty?

        FeatureAggregate.new(feature_id, events)
      end

      # Save feature aggregate to event store
      def save(aggregate, expected_version: nil)
        return if aggregate.uncommitted_events.empty?

        @event_store.append(
          aggregate.id,
          aggregate.uncommitted_events,
          expected_version: expected_version
        )

        aggregate.mark_events_as_committed
      end

      # Find or create feature aggregate
      def find_or_create(feature_id)
        find(feature_id) || FeatureAggregate.new(feature_id)
      end

      # Check if feature exists
      def exists?(feature_id)
        @event_store.get_version(feature_id).positive?
      end

      # Get all feature IDs that have events
      def all_feature_ids
        # This would need to be implemented by the event store adapter
        # For now, we'll return an empty array as this requires scanning
        []
      end

      # Get features by state (requires read model/projection)
      def find_by_state(state)
        # This would typically be implemented using a read model/projection
        # For now, we'll raise an error to indicate this needs a projection
        raise NotImplementedError, 'Use FeatureProjection to query by state'
      end

      # Health check
      def healthy?
        @event_store.respond_to?(:healthy?) ? @event_store.healthy? : true
      end

      private

      attr_reader :event_store
    end
  end
end
