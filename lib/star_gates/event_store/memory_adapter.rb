# frozen_string_literal: true

require 'concurrent'

module StarGates
  module EventStore
    class MemoryAdapter
      def initialize
        @events = Concurrent::Hash.new { |h, k| h[k] = Concurrent::Array.new }
        @global_events = Concurrent::Array.new
        @versions = Concurrent::Hash.new(0)
        @mutex = Mutex.new
      end

      def append(aggregate_id, events)
        @mutex.synchronize do
          events.each do |event|
            # Increment version
            @versions[aggregate_id] += 1
            versioned_event = event.dup.tap do |e|
              e.instance_variable_set(:@version, @versions[aggregate_id])
            end

            # Store by aggregate
            @events[aggregate_id] << versioned_event

            # Store globally for cross-aggregate queries
            @global_events << versioned_event
          end
        end
      end

      def get_events(aggregate_id, from_version: 0)
        @events[aggregate_id].select { |event| event.version > from_version }
      end

      def get_events_from(timestamp, limit: 100)
        @global_events
          .select { |event| event.occurred_at >= timestamp }
          .sort_by(&:occurred_at)
          .reverse
          .first(limit)
      end

      def get_events_by_type(event_type, limit: 100)
        @global_events
          .select { |event| event.event_type == event_type }
          .sort_by(&:occurred_at)
          .reverse
          .first(limit)
      end

      def get_version(aggregate_id)
        @versions[aggregate_id]
      end

      def replay_all(&)
        @global_events.sort_by(&:occurred_at).each(&)
      end

      def clear!
        @mutex.synchronize do
          @events.clear
          @global_events.clear
          @versions.clear
        end
      end

      def size
        @global_events.size
      end

      def aggregate_count
        @events.size
      end
    end
  end
end
