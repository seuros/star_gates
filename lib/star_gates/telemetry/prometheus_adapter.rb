# frozen_string_literal: true

require_relative 'telemetry_adapter'

module StarGates
  module Telemetry
    # Prometheus records durations in seconds, its base unit: the Integer
    # nanoseconds handed in are converted here, at the boundary.
    class PrometheusAdapter < TelemetryAdapter
      NS_PER_SECOND = 1_000_000_000
      SECONDS_BUCKETS = [0.0001, 0.0005, 0.001, 0.0025, 0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1].freeze
      private_constant :NS_PER_SECOND, :SECONDS_BUCKETS

      def initialize(config = {})
        super
        @prometheus = config[:prometheus] || default_prometheus
        @metric_prefix = config[:metric_prefix] || 'star_gates'
        @registry = {}
        setup_default_metrics
      end

      def healthy?
        super && @prometheus.respond_to?(:registry)
      end

      # Use pre-registered metrics for better performance
      def record_feature_evaluation(feature_id, eligible, _context, execution_time = nil)
        return unless enabled?

        tags = {
          feature_id: feature_id.to_s,
          eligible: eligible.to_s
        }

        @registry[:feature_evaluations].increment(labels: tags)

        return unless execution_time

        @registry[:evaluation_duration].observe(seconds(execution_time), labels: {
                                                  feature_id: feature_id.to_s,
                                                  eligible: eligible.to_s
                                                })
      end

      def record_feature_execution(feature_id, state, success, execution_time, _context = {})
        return unless enabled?

        execution_tags = {
          feature_id: feature_id.to_s,
          state: state.to_s,
          success: success.to_s
        }

        duration_tags = {
          feature_id: feature_id.to_s,
          state: state.to_s
        }

        @registry[:feature_executions].increment(labels: execution_tags)
        @registry[:execution_duration].observe(seconds(execution_time), labels: duration_tags)
      end

      def record_state_transition(feature_id, from_state, to_state, event_name)
        return unless enabled?

        tags = {
          feature_id: feature_id.to_s,
          from_state: from_state.to_s,
          to_state: to_state.to_s,
          event: event_name.to_s
        }

        @registry[:state_transitions].increment(labels: tags)
      end

      def record_system_health(healthy, component_healths = {})
        return unless enabled?

        @registry[:system_health].set(healthy ? 1 : 0, labels: { component: 'overall' })

        component_healths.each do |component, health|
          @registry[:system_health].set(health ? 1 : 0, labels: { component: component.to_s })
        end
      end

      protected

      def send_metric(name, value, tags, _timestamp)
        metric_name = "#{@metric_prefix}_#{name}".gsub('.', '_')

        case name
        when /\.gauge$/
          get_or_create_gauge(metric_name, tags).set(value)
        when /\.timing$/
          get_or_create_histogram(metric_name, tags).observe(seconds(value))
        when /\.histogram$/
          get_or_create_histogram(metric_name, tags).observe(value)
        else
          # Default to counter
          get_or_create_counter(metric_name, tags).increment(by: value)
        end
      end

      private

      def default_prometheus
        unless defined?(Prometheus)
          raise ArgumentError, "Prometheus gem not available. Install with: gem 'prometheus-client'"
        end

        Prometheus
      end

      def setup_default_metrics
        # Pre-register common metrics for better performance
        @registry[:feature_evaluations] = @prometheus.counter(
          :"#{@metric_prefix}_feature_evaluations_total",
          docstring: 'Total number of feature flag evaluations',
          labels: %i[feature_id eligible]
        )

        @registry[:feature_executions] = @prometheus.counter(
          :"#{@metric_prefix}_feature_executions_total",
          docstring: 'Total number of feature flag executions',
          labels: %i[feature_id state success]
        )

        @registry[:state_transitions] = @prometheus.counter(
          :"#{@metric_prefix}_state_transitions_total",
          docstring: 'Total number of feature flag state transitions',
          labels: %i[feature_id from_state to_state event]
        )

        @registry[:execution_duration] = @prometheus.histogram(
          :"#{@metric_prefix}_execution_duration_seconds",
          docstring: 'Feature execution duration in seconds',
          labels: %i[feature_id state],
          buckets: SECONDS_BUCKETS
        )

        @registry[:evaluation_duration] = @prometheus.histogram(
          :"#{@metric_prefix}_evaluation_duration_seconds",
          docstring: 'Feature evaluation duration in seconds',
          labels: %i[feature_id eligible],
          buckets: SECONDS_BUCKETS
        )

        @registry[:system_health] = @prometheus.gauge(
          :"#{@metric_prefix}_system_health",
          docstring: 'System health status (1 = healthy, 0 = unhealthy)',
          labels: [:component]
        )
      end

      def get_or_create_counter(name, tags)
        key = "#{name}_counter"
        @registry[key] ||= @prometheus.counter(
          name.to_sym,
          docstring: "Counter metric for #{name}",
          labels: tags.keys
        )
        @registry[key].with(tags)
      end

      def get_or_create_gauge(name, tags)
        key = "#{name}_gauge"
        @registry[key] ||= @prometheus.gauge(
          name.to_sym,
          docstring: "Gauge metric for #{name}",
          labels: tags.keys
        )
        @registry[key].with(tags)
      end

      def get_or_create_histogram(name, tags)
        key = "#{name}_histogram"
        @registry[key] ||= @prometheus.histogram(
          name.to_sym,
          docstring: "Histogram metric for #{name}",
          labels: tags.keys,
          buckets: SECONDS_BUCKETS
        )
        @registry[key].with(tags)
      end

      def seconds(nanoseconds)
        Rational(nanoseconds, NS_PER_SECOND).to_f
      end
    end
  end
end
