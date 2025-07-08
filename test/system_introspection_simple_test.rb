# frozen_string_literal: true

require 'test_helper'

class TestSystemIntrospectionSimple < Minitest::Test
  def setup
    StarGates.reset!

    # Create gates manually without DSL
    feature1 = StarGates::Feature.new(rollout: 25, group: :beta_users)
    feature2 = StarGates::Feature.new(rollout: 50)
    feature3 = StarGates::Feature.new(rollout: 0)

    gate1 = StarGates::Gate.new(:payment_v2, feature: feature1)
    gate2 = StarGates::Gate.new(:dashboard_redesign, feature: feature2)
    gate3 = StarGates::Gate.new(:experimental_feature, feature: feature3)

    StarGates.registry.register(:payment_v2, gate1)
    StarGates.registry.register(:dashboard_redesign, gate2)
    StarGates.registry.register(:experimental_feature, gate3)

    # Set some features to different states
    feature1.rollout_canary
    feature2.enable
    # feature3 stays disabled
  end

  def test_feature_overview
    overview = StarGates.feature_overview

    assert_equal 3, overview[:total_gates]
    assert_equal 3, overview[:gates].size

    # Check summary statistics
    summary = overview[:summary]
    assert_equal 3, summary[:total_features]
    assert_equal 1, summary[:by_status]['disabled']
    assert_equal 1, summary[:by_status]['enabled']
    assert_equal 1, summary[:by_status]['canary']

    # Check individual gate info
    payment_gate = overview[:gates][:payment_v2]
    assert_equal :payment_v2, payment_gate[:name]
    assert payment_gate[:feature]
    assert_equal 'canary', payment_gate[:feature][:status]

    dashboard_gate = overview[:gates][:dashboard_redesign]
    assert_equal 'enabled', dashboard_gate[:feature][:status]

    experimental_gate = overview[:gates][:experimental_feature]
    assert_equal 'disabled', experimental_gate[:feature][:status]
  end

  def test_rollout_statistics
    stats = StarGates.rollout_statistics

    assert_equal 3, stats[:total_gates]
    assert_equal 1, stats[:features_by_status]['disabled']
    assert_equal 1, stats[:features_by_status]['enabled']
    assert_equal 1, stats[:features_by_status]['canary']

    # Check rollout distribution
    assert stats[:rollout_distribution].key?('10-24%') || stats[:rollout_distribution].key?('25-49%')

    # Check average rollout (only canary features count)
    assert stats[:average_rollout] >= 0

    assert stats[:generated_at]
  end

  def test_state_distribution
    distribution = StarGates.state_distribution

    assert_equal 3, distribution[:total]
    assert_equal 1, distribution[:distribution]['disabled']
    assert_equal 1, distribution[:distribution]['enabled']
    assert_equal 1, distribution[:distribution]['canary']

    # Check percentages
    percentages = distribution[:percentages]
    assert_equal 33.33, percentages['disabled']
    assert_equal 33.33, percentages['enabled']
    assert_equal 33.33, percentages['canary']
  end

  def test_recent_transitions
    transitions = StarGates.recent_transitions

    # Should have recorded the transitions from setup
    assert_equal 2, transitions[:transitions].size
    assert_equal 2, transitions[:total_found]
    assert_equal 10, transitions[:limit]

    # Check the transition structure
    transition = transitions[:transitions].first
    assert transition[:timestamp]
    assert transition[:feature_name]
    assert transition[:feature_class]
    assert transition[:from_state]
    assert transition[:to_state]
    assert transition[:event]
    assert transition[:duration_since]
  end

  def test_feature_overview_with_no_gates
    StarGates.reset!
    overview = StarGates.feature_overview

    assert_equal 0, overview[:total_gates]
    assert_equal 0, overview[:gates].size
    assert_equal 0, overview[:summary][:total_features]
  end

  def test_rollout_statistics_with_no_gates
    StarGates.reset!
    stats = StarGates.rollout_statistics

    assert_equal 0, stats[:total_gates]
    assert_equal 0, stats[:average_rollout]
    assert_equal({}, stats[:rollout_distribution])
  end

  def test_circuit_info_helper_method
    # Test the private circuit_info method indirectly through feature_overview
    overview = StarGates.feature_overview

    # Our test gates don't have circuits, so circuit should be nil
    overview[:gates].each_value do |gate_info|
      assert_nil gate_info[:circuit]
    end
  end
end
