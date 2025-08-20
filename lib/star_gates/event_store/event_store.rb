# frozen_string_literal: true

module StarGates
  module EventStore
    class EventStore
      def initialize(adapter: nil)
        @adapter = adapter || MemoryAdapter.new
        @subscribers = Hash.new { |h, k| h[k] = [] }
      end

      # Append events to the store
      def append(aggregate_id, events, expected_version: nil)
        events = Array(events)
        return if events.empty?

        # Validate expected version for optimistic concurrency
        if expected_version
          current_version = @adapter.get_version(aggregate_id)
          if current_version != expected_version
            raise ConcurrencyError, "Expected version #{expected_version}, got #{current_version}"
          end
        end

        # Store events
        @adapter.append(aggregate_id, events)

        # Notify subscribers
        events.each do |event|
          notify_subscribers(event)
        end

        events.size
      end

      # Get events for an aggregate
      def get_events(aggregate_id, from_version: 0)
        @adapter.get_events(aggregate_id, from_version: from_version)
      end

      # Get all events from a specific time
      def get_events_from(timestamp, limit: 100)
        @adapter.get_events_from(timestamp, limit: limit)
      end

      # Get events by type
      def get_events_by_type(event_type, limit: 100)
        @adapter.get_events_by_type(event_type, limit: limit)
      end

      # Subscribe to events
      def subscribe(event_type = nil, &block)
        key = event_type || :all
        @subscribers[key] << block
      end

      # Get current version of aggregate
      def get_version(aggregate_id)
        @adapter.get_version(aggregate_id)
      end

      # Replay all events to rebuild projections
      def replay_all(&)
        @adapter.replay_all(&)
      end

      private

      def notify_subscribers(event)
        # Notify specific event type subscribers
        @subscribers[event.event_type].each { |subscriber| subscriber.call(event) }

        # Notify all event subscribers
        @subscribers[:all].each { |subscriber| subscriber.call(event) }
      end
    end

    class ConcurrencyError < StandardError; end
  end
end
