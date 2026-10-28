# frozen_string_literal: true

module StarGates
  module Telemetry
    class TelemetryAdapter
      def initialize(config = {})
        @config = config
        @enabled = config.fetch(:enabled, true)
      end

      # Core telemetry methods
      def record_metric(name, value, tags: {}, timestamp: Time.now)
        return unless enabled?

        send_metric(name, value, tags, timestamp)
      end

      def record_counter(name, value = 1, tags: {})
        return unless enabled?

        record_metric("#{name}.count", value, tags: tags)
      end

      def record_gauge(name, value, tags: {})
        return unless enabled?

        record_metric("#{name}.gauge", value, tags: tags)
      end

      def record_histogram(name, value, tags: {})
        return unless enabled?

        record_metric("#{name}.histogram", value, tags: tags)
      end

      def record_timing(name, duration_ms, tags: {})
        return unless enabled?

        record_metric("#{name}.timing", duration_ms, tags: tags)
      end

      # Feature flag specific metrics
      def record_feature_evaluation(feature_id, eligible, _context, execution_time_ms = nil)
        return unless enabled?

        tags = {
          feature_id: feature_id,
          eligible: eligible
        }

        record_counter('star_gates.feature.evaluation', 1, tags: tags)

        return unless execution_time_ms

        record_timing('star_gates.feature.evaluation.duration', execution_time_ms, tags: tags)
      end

      def record_feature_execution(feature_id, state, success, execution_time_ms, _context = {})
        return unless enabled?

        tags = {
          feature_id: feature_id,
          state: state,
          success: success
        }

        record_counter('star_gates.feature.execution', 1, tags: tags)
        record_timing('star_gates.feature.execution.duration', execution_time_ms, tags: tags)
      end

      def record_state_transition(feature_id, from_state, to_state, event_name)
        return unless enabled?

        tags = {
          feature_id: feature_id,
          from_state: from_state,
          to_state: to_state,
          event: event_name
        }

        record_counter('star_gates.feature.transition', 1, tags: tags)
      end

      def record_circuit_breaker_event(feature_id, event_type, state)
        return unless enabled?

        tags = {
          feature_id: feature_id,
          event_type: event_type,
          circuit_state: state
        }

        record_counter('star_gates.circuit_breaker.event', 1, tags: tags)
      end

      # System metrics
      def record_system_health(healthy, component_healths = {})
        return unless enabled?

        record_gauge('star_gates.system.healthy', healthy ? 1 : 0)

        component_healths.each do |component, health|
          record_gauge('star_gates.system.component.healthy', health ? 1 : 0,
                       tags: { component: component })
        end
      end

      def record_event_store_metrics(event_count, aggregate_count, projection_lag_ms = nil)
        return unless enabled?

        record_gauge('star_gates.event_store.events', event_count)
        record_gauge('star_gates.event_store.aggregates', aggregate_count)

        return unless projection_lag_ms

        record_timing('star_gates.event_store.projection_lag', projection_lag_ms)
      end

      # Time a block and record the duration
      def time(metric_name, tags: {}, &block)
        return block.call unless enabled?

        start_time = Time.now
        result = block.call
        duration_ms = ((Time.now - start_time) * 1000).round(2)

        record_timing(metric_name, duration_ms, tags: tags)
        result
      end

      # Health check
      def healthy?
        enabled?
      end

      def enabled?
        @enabled
      end

      def disable!
        @enabled = false
      end

      def enable!
        @enabled = true
      end

      protected

      # Subclasses must implement this
      def send_metric(name, value, tags, timestamp)
        raise NotImplementedError, 'Subclasses must implement #send_metric'
      end

      private

      attr_reader :config
    end
  end
end
