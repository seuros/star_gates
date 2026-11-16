# frozen_string_literal: true

require 'test_helper'

class TelemetryContextTest < Minitest::Test
  class RecordingAdapter < StarGates::Telemetry::TelemetryAdapter
    attr_reader :metrics

    def initialize
      super
      @metrics = []
    end

    protected

    def send_metric(name, value, tags, _timestamp)
      metrics << { name: name, value: value, tags: tags }
    end
  end

  def test_evaluation_metrics_are_independent_of_rollout_identity
    adapter = RecordingAdapter.new
    adapter.record_feature_evaluation('preview', true, { key: 'device:42', groups: [:beta] }, 1_500_000)

    assert_equal 2, adapter.metrics.size
    adapter.metrics.each do |metric|
      assert_equal({ feature_id: 'preview', eligible: true }, metric[:tags])
    end
  end

  def test_event_attribution_is_explicit_metadata
    event = StarGates::Events::BaseEvent.new(aggregate_id: 'preview', metadata: { created_by: 'deployment:42' })

    assert_equal 'deployment:42', event.metadata[:created_by]
  end

  def test_base_adapter_metrics_carry_nanoseconds
    adapter = RecordingAdapter.new
    adapter.record_metric('m', 1, tags: { a: 1 }, timestamp: 5)
    adapter.record_counter('c')
    adapter.record_gauge('g', 2)
    adapter.record_histogram('h', 3)
    adapter.record_timing('t', 4_000)
    adapter.record_circuit_breaker_event('f', :opened, :open)
    adapter.record_event_store_metrics(10, 2, 7_000)
    adapter.record_system_health(true, store: false)
    adapter.record_state_transition('f', :disabled, :enabled, :enable)
    adapter.record_feature_execution('f', 'enabled', true, 9_000)

    names = adapter.metrics.map { |metric| metric[:name] }
    assert_includes names, 'c.count'
    assert_includes names, 'g.gauge'
    assert_includes names, 'h.histogram'
    assert_includes names, 'star_gates.event_store.projection_lag.timing'
    assert_equal 4_000, adapter.metrics.find { |metric| metric[:name] == 't.timing' }[:value]
  end

  def test_time_records_integer_nanoseconds
    adapter = RecordingAdapter.new

    assert_equal :ok, adapter.time('block') { :ok }
    assert_kind_of Integer, adapter.metrics.last[:value]
  end

  def test_disable_and_enable
    adapter = RecordingAdapter.new
    adapter.disable!
    refute adapter.enabled?
    refute adapter.healthy?
    adapter.record_counter('c')
    assert_empty adapter.metrics
    assert_equal :ran, adapter.time('t') { :ran }
    adapter.enable!
    assert adapter.enabled?
  end
end
