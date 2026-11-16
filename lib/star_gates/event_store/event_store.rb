# frozen_string_literal: true

module StarGates
  module EventStore
    class EventStore
      def initialize(adapter: nil)
        @adapter = adapter || MemoryAdapter.new
        @subscribers = Hash.new { |h, k| h[k] = [] }
      end

      # Appends the events and answers how many, or :version_conflict when
      # `expected_version` is not the aggregate's version (nothing stored).
      def append(aggregate_id, events, expected_version: nil)
        events = Array(events)
        return 0 if events.empty?
        return :version_conflict unless @adapter.append(aggregate_id, events, expected_version)

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

      # Events at or after `timestamp` (wall-clock Integer nanoseconds),
      # newest first.
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
  end
end
