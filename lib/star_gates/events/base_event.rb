# frozen_string_literal: true

require 'securerandom'

module StarGates
  module Events
    class BaseEvent
      attr_reader :event_id, :aggregate_id, :event_type, :data, :metadata, :occurred_at, :version

      def initialize(aggregate_id:, data: {}, metadata: {}, version: 1)
        @event_id = SecureRandom.uuid
        @aggregate_id = aggregate_id
        @event_type = self.class.name.split('::').last
        @data = data.freeze
        @metadata = metadata.merge(
          source: 'star_gates',
          correlation_id: Thread.current[:correlation_id] || SecureRandom.uuid
        ).freeze
        @occurred_at = Time.now.utc
        @version = version
        freeze
      end

      def to_h
        {
          event_id: event_id,
          aggregate_id: aggregate_id,
          event_type: event_type,
          data: data,
          metadata: metadata,
          occurred_at: occurred_at,
          version: version
        }
      end

      def ==(other)
        other.is_a?(self.class) && event_id == other.event_id
      end

      def hash
        event_id.hash
      end
    end
  end
end
