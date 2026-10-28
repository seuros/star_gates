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
    adapter.record_feature_evaluation('preview', true, { key: 'device:42', groups: [:beta] }, 1.5)

    assert_equal 2, adapter.metrics.size
    adapter.metrics.each do |metric|
      assert_equal({ feature_id: 'preview', eligible: true }, metric[:tags])
    end
  end

  def test_event_attribution_is_explicit_metadata
    event = StarGates::Events::BaseEvent.new(aggregate_id: 'preview', metadata: { created_by: 'deployment:42' })

    assert_equal 'deployment:42', event.metadata[:created_by]
  end
end
