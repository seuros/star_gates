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

      # Stores the aggregate's uncommitted events and answers how many, or
      # :version_conflict (the aggregate keeps them; nothing is stored).
      def save(aggregate, expected_version: nil)
        stored = @event_store.append(aggregate.id, aggregate.uncommitted_events, expected_version: expected_version)
        aggregate.mark_events_as_committed if stored.is_a?(Integer)
        stored
      end

      # Find or create feature aggregate
      def find_or_create(feature_id)
        find(feature_id) || FeatureAggregate.new(feature_id)
      end

      # Check if feature exists
      def exists?(feature_id)
        @event_store.get_version(feature_id).positive?
      end

      # Health check
      def healthy?
        @event_store.respond_to?(:healthy?) ? @event_store.healthy? : true
      end

    end
  end
end
