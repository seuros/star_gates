# frozen_string_literal: true

require_relative 'telemetry_adapter'

module StarGates
  module Telemetry
    class OpentelemetryAdapter < TelemetryAdapter
      def initialize(config = {})
        super
        @tracer = config[:tracer] || default_tracer
        @meter = config[:meter] || default_meter
        @service_name = config[:service_name] || 'star_gates'
        @service_version = config[:service_version] || StarGates::VERSION
        setup_instruments
      end

      # OpenTelemetry-specific methods
      def trace_feature_evaluation(feature_id, _context, &block)
        return block.call unless enabled?

        @tracer.in_span('feature.evaluate', attributes: {
                          'feature.id' => feature_id,
                          'service.name' => @service_name,
                          'service.version' => @service_version
                        }) do |span|
          start_time = Time.now
          result = block.call
          duration = ((Time.now - start_time) * 1000).round(2)

          span.set_attribute('feature.eligible', result[:eligible]) if result.is_a?(Hash)
          span.set_attribute('feature.evaluation.duration_ms', duration)
          span.status = OpenTelemetry::Trace::Status.ok

          result
        end
      end

      def trace_feature_execution(feature_id, state, &block)
        return block.call unless enabled?

        @tracer.in_span('feature.execute', attributes: {
                          'feature.id' => feature_id,
                          'feature.state' => state,
                          'service.name' => @service_name,
                          'service.version' => @service_version
                        }) do |span|
          start_time = Time.now
          begin
            result = block.call
            duration = ((Time.now - start_time) * 1000).round(2)

            span.set_attribute('feature.execution.duration_ms', duration)
            span.set_attribute('feature.execution.success', true)
            span.status = OpenTelemetry::Trace::Status.ok

            result
          rescue StandardError => e
            duration = ((Time.now - start_time) * 1000).round(2)
            span.set_attribute('feature.execution.duration_ms', duration)
            span.set_attribute('feature.execution.success', false)
            span.set_attribute('feature.execution.error', e.message)
            span.status = OpenTelemetry::Trace::Status.error(e.message)
            raise
          end
        end
      end

      def trace_state_transition(feature_id, from_state, to_state, event_name, &block)
        return block.call unless enabled?

        @tracer.in_span('feature.state_transition', attributes: {
                          'feature.id' => feature_id,
                          'feature.transition.from' => from_state,
                          'feature.transition.to' => to_state,
                          'feature.transition.event' => event_name,
                          'service.name' => @service_name,
                          'service.version' => @service_version
                        }) do |span|
          result = block.call
          span.status = OpenTelemetry::Trace::Status.ok
          result
        end
      end

      protected

      def send_metric(name, value, tags, _timestamp)
        # Convert tags to OpenTelemetry attributes
        attributes = tags.transform_keys(&:to_s)
        attributes['service.name'] = @service_name
        attributes['service.version'] = @service_version

        case name
        when /\.count$/
          instrument_name = name.gsub(/\.count$/, '').gsub('.', '_')
          counter = @instruments["#{instrument_name}_total"] ||=
            @meter.create_counter("star_gates_#{instrument_name}_total",
                                  unit: '1',
                                  description: "Total count of #{instrument_name}")
          counter.add(value, attributes: attributes)

        when /\.gauge$/
          instrument_name = name.gsub(/\.gauge$/, '').gsub('.', '_')
          @instruments[instrument_name] ||=
            @meter.create_observable_gauge("star_gates_#{instrument_name}",
                                           unit: '1',
                                           description: "Current value of #{instrument_name}")
          # NOTE: OpenTelemetry gauges are observable, so we store the value
          @gauge_values ||= {}
          @gauge_values["#{instrument_name}_#{attributes.hash}"] = { value: value, attributes: attributes }

        when /\.histogram$/, /\.timing$/
          instrument_name = name.gsub(/\.(histogram|timing)$/, '').gsub('.', '_')
          histogram = @instruments["#{instrument_name}_duration"] ||=
            @meter.create_histogram("star_gates_#{instrument_name}_duration",
                                    unit: 'ms',
                                    description: "Duration histogram for #{instrument_name}")
          histogram.record(value, attributes: attributes)
        end
      end

      def healthy?
        super && @tracer.respond_to?(:in_span) && @meter.respond_to?(:create_counter)
      end

      private

      def default_tracer
        unless defined?(OpenTelemetry)
          raise ArgumentError, "OpenTelemetry gem not available. Install with: gem 'opentelemetry-sdk'"
        end

        OpenTelemetry.tracer_provider.tracer(@service_name, @service_version)
      end

      def default_meter
        unless defined?(OpenTelemetry)
          raise ArgumentError, "OpenTelemetry gem not available. Install with: gem 'opentelemetry-sdk'"
        end

        OpenTelemetry.meter_provider.meter(@service_name, @service_version)
      end

      def setup_instruments
        @instruments = {}
        @gauge_values = {}

        # Pre-create common instruments
        @instruments['feature_evaluations_total'] = @meter.create_counter(
          'star_gates_feature_evaluations_total',
          unit: '1',
          description: 'Total number of feature evaluations'
        )

        @instruments['feature_executions_total'] = @meter.create_counter(
          'star_gates_feature_executions_total',
          unit: '1',
          description: 'Total number of feature executions'
        )

        @instruments['state_transitions_total'] = @meter.create_counter(
          'star_gates_state_transitions_total',
          unit: '1',
          description: 'Total number of state transitions'
        )

        @instruments['evaluation_duration'] = @meter.create_histogram(
          'star_gates_evaluation_duration',
          unit: 'ms',
          description: 'Feature evaluation duration'
        )

        @instruments['execution_duration'] = @meter.create_histogram(
          'star_gates_execution_duration',
          unit: 'ms',
          description: 'Feature execution duration'
        )

        # Setup observable gauge for system health
        @meter.create_observable_gauge(
          'star_gates_system_health',
          unit: '1',
          description: 'System health status'
        ) do |observer|
          @gauge_values.each do |key, data|
            next unless key.include?('system_health')

            observer.observe(data[:value], attributes: data[:attributes])
          end
        end
      end

      # Override specific methods to use pre-created instruments
      def record_feature_evaluation(feature_id, eligible, _context, execution_time_ms = nil)
        return unless enabled?

        attributes = {
          'feature.id' => feature_id.to_s,
          'feature.eligible' => eligible.to_s,
          'service.name' => @service_name,
          'service.version' => @service_version
        }

        @instruments['feature_evaluations_total'].add(1, attributes: attributes)

        return unless execution_time_ms

        @instruments['evaluation_duration'].record(execution_time_ms, attributes: {
                                                     'feature.id' => feature_id.to_s,
                                                     'feature.eligible' => eligible.to_s,
                                                     'service.name' => @service_name,
                                                     'service.version' => @service_version
                                                   })
      end

      def record_feature_execution(feature_id, state, success, execution_time_ms, _context = {})
        return unless enabled?

        attributes = {
          'feature.id' => feature_id.to_s,
          'feature.state' => state.to_s,
          'feature.success' => success.to_s,
          'service.name' => @service_name,
          'service.version' => @service_version
        }

        @instruments['feature_executions_total'].add(1, attributes: attributes)
        @instruments['execution_duration'].record(execution_time_ms, attributes: {
                                                    'feature.id' => feature_id.to_s,
                                                    'feature.state' => state.to_s,
                                                    'service.name' => @service_name,
                                                    'service.version' => @service_version
                                                  })
      end

      def record_state_transition(feature_id, from_state, to_state, event_name)
        return unless enabled?

        attributes = {
          'feature.id' => feature_id.to_s,
          'feature.transition.from' => from_state.to_s,
          'feature.transition.to' => to_state.to_s,
          'feature.transition.event' => event_name.to_s,
          'service.name' => @service_name,
          'service.version' => @service_version
        }

        @instruments['state_transitions_total'].add(1, attributes: attributes)
      end
    end
  end
end
