# frozen_string_literal: true

require 'test_helper'
require 'star_gates/telemetry/prometheus_adapter'
require 'star_gates/telemetry/opentelemetry_adapter'

# The backend adapters against recording stand-ins for their client gems.
class TelemetryAdaptersTest < Minitest::Test
  # Stand-in for a prometheus-client metric.
  class FakeMetric
    attr_reader :name, :options, :calls

    def initialize(name, options)
      @name = name
      @options = options
      @calls = []
    end

    def increment(by: 1, labels: {}) = calls << [:increment, by, labels]
    def observe(value, labels: {}) = calls << [:observe, value, labels]
    def set(value, labels: {}) = calls << [:set, value, labels]
    def with(_tags) = self
  end

  # Stand-in for the Prometheus module.
  class FakePrometheus
    attr_reader :metrics

    def initialize
      @metrics = {}
    end

    def registry = self

    %i[counter histogram gauge].each do |kind|
      define_method(kind) { |name, **options| metrics[name] = FakeMetric.new(name, options) }
    end
  end

  # Stand-in for an OpenTelemetry instrument.
  class FakeInstrument
    attr_reader :calls

    def initialize
      @calls = []
    end

    def add(value, attributes: {}) = calls << [:add, value, attributes]
    def record(value, attributes: {}) = calls << [:record, value, attributes]
  end

  # Stand-in for an OpenTelemetry meter.
  class FakeMeter
    attr_reader :instruments

    def initialize
      @instruments = {}
    end

    def create_counter(name, **) = instruments[name] = FakeInstrument.new
    def create_histogram(name, **) = instruments[name] = FakeInstrument.new
    def create_observable_gauge(name, **) = instruments[name] = FakeInstrument.new
  end

  # Stand-in for an OpenTelemetry span.
  class FakeSpan
    attr_reader :attributes
    attr_accessor :status

    def initialize
      @attributes = {}
    end

    def set_attribute(key, value) = attributes[key] = value
  end

  # Stand-in for an OpenTelemetry tracer.
  class FakeTracer
    attr_reader :spans

    def initialize
      @spans = []
    end

    def in_span(*, **) = yield(FakeSpan.new.tap { |span| spans << span })
  end

  # The trace helpers name OpenTelemetry::Trace::Status; each test runs in
  # its own fork, so defining the stand-in here leaks nowhere.
  def stub_opentelemetry_status
    return if defined?(::OpenTelemetry::Trace::Status)

    status = Module.new do
      def self.ok = :ok
      def self.error(message) = [:error, message]
    end
    Object.const_set(:OpenTelemetry, Module.new) unless defined?(::OpenTelemetry)
    ::OpenTelemetry.const_set(:Trace, Module.new) unless defined?(::OpenTelemetry::Trace)
    ::OpenTelemetry::Trace.const_set(:Status, status)
  end

  def prometheus_adapter
    @prometheus = FakePrometheus.new
    StarGates::Telemetry::PrometheusAdapter.new(prometheus: @prometheus)
  end

  def opentelemetry_adapter
    @meter = FakeMeter.new
    @tracer = FakeTracer.new
    StarGates::Telemetry::OpentelemetryAdapter.new(tracer: @tracer, meter: @meter)
  end

  # Bug: the feature-metric overrides sat below `private` and `healthy?`
  # below `protected`, so calling them on a backend adapter raised
  # NoMethodError.
  def test_prometheus_adapter_methods_are_public
    adapter = prometheus_adapter

    adapter.record_feature_execution('checkout', 'enabled', true, 2_500_000)
    adapter.record_feature_evaluation('checkout', true, {}, 500_000)
    adapter.record_state_transition('checkout', :disabled, :enabled, :enable)
    adapter.record_system_health(true, store: false)
    assert adapter.healthy?
  end

  def test_prometheus_durations_are_seconds
    adapter = prometheus_adapter
    adapter.record_feature_execution('checkout', 'enabled', true, 2_500_000)

    histogram = @prometheus.metrics.fetch(:star_gates_execution_duration_seconds)
    assert_equal [[:observe, 0.0025, { feature_id: 'checkout', state: 'enabled' }]], histogram.calls
  end

  def test_prometheus_timing_is_seconds
    adapter = prometheus_adapter
    adapter.record_timing('lookup', 1_000_000_000)

    histogram = @prometheus.metrics.fetch(:star_gates_lookup_timing)
    assert_equal [[:observe, 1.0, {}]], histogram.calls
  end

  def test_opentelemetry_adapter_methods_are_public
    adapter = opentelemetry_adapter

    adapter.record_feature_execution('checkout', 'enabled', true, 2_500_000)
    adapter.record_feature_evaluation('checkout', true, {}, 500_000)
    adapter.record_state_transition('checkout', :disabled, :enabled, :enable)
    assert adapter.healthy?
  end

  def test_opentelemetry_durations_are_integer_nanoseconds
    adapter = opentelemetry_adapter
    adapter.record_feature_execution('checkout', 'enabled', true, 2_500_000)

    histogram = @meter.instruments.fetch('star_gates_execution_duration')
    assert_equal 2_500_000, histogram.calls.first[1]
  end

  def test_opentelemetry_traces_run_the_block
    stub_opentelemetry_status
    adapter = opentelemetry_adapter

    assert_equal :ran, adapter.trace_feature_execution('checkout', 'enabled') { :ran }
    assert_equal({ eligible: true }, adapter.trace_feature_evaluation('checkout', {}) { { eligible: true } })
    assert_equal :ran, adapter.trace_state_transition('checkout', :disabled, :enabled, :enable) { :ran }
    assert_kind_of Integer, @tracer.spans.first.attributes['feature.execution.duration_ns']
    assert_kind_of Integer, @tracer.spans[1].attributes['feature.evaluation.duration_ns']
  end

  def test_opentelemetry_trace_reraises_and_marks_the_span
    stub_opentelemetry_status
    adapter = opentelemetry_adapter

    assert_raises(RuntimeError) { adapter.trace_feature_execution('checkout', 'enabled') { raise 'boom' } }
    assert_equal [:error, 'boom'], @tracer.spans.first.status
    refute @tracer.spans.first.attributes['feature.execution.success']
  end
end
