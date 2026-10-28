# frozen_string_literal: true

require 'test_helper'

class TestSystemIntrospection < Minitest::Test
  def setup
    StarGates.reset!

    # Create some test gates with features
    StarGates.define do
      gate :payment_v2 do
        feature rollout: 25, group: :beta
        run { 'new payment' }
        fallback { 'old payment' }
      end

      gate :dashboard_redesign do
        feature rollout: 50
        run { 'new dashboard' }
        fallback { 'old dashboard' }
      end

      gate :experimental_feature do
        feature rollout: 0
        run { 'experimental' }
        fallback { 'stable' }
      end
    end

    # Set some features to different states
    StarGates[:payment_v2].feature.rollout_canary
    StarGates[:dashboard_redesign].feature.enable
    # experimental_feature stays disabled
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

  def test_recent_transitions_with_custom_limit
    transitions = StarGates.recent_transitions(limit: 5)

    assert_equal 5, transitions[:limit]
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

  def test_state_distribution_with_no_gates
    StarGates.reset!
    distribution = StarGates.state_distribution

    assert_equal 0, distribution[:total]
    assert_equal({}, distribution[:distribution])
  end

  def test_circuit_info_helper_method
    # Test the private circuit_info method indirectly through feature_overview
    overview = StarGates.feature_overview

    # Our test gates don't have circuits, so circuit should be nil
    overview[:gates].each_value do |gate_info|
      assert_nil gate_info[:circuit]
    end
  end

  def test_system_introspection_with_mixed_feature_states
    # Create more complex scenario
    StarGates.reset!

    StarGates.define do
      5.times do |i|
        gate :"feature_#{i}" do
          feature rollout: i * 20
          run { "feature #{i}" }
          fallback { "fallback #{i}" }
        end
      end
    end

    # Set different states
    # Leave feature_0 disabled (no state change)
    StarGates[:feature_1].feature.rollout_canary  # 20% rollout
    StarGates[:feature_2].feature.enable          # enabled
    StarGates[:feature_3].feature.rollout_canary  # 60% rollout
    StarGates[:feature_4].feature.enable          # enabled

    stats = StarGates.rollout_statistics
    assert_equal 5, stats[:total_gates]
    assert_equal 1, stats[:features_by_status]['disabled']
    assert_equal 2, stats[:features_by_status]['enabled']
    assert_equal 2, stats[:features_by_status]['canary']

    distribution = StarGates.state_distribution
    assert_equal 5, distribution[:total]
    assert_equal 20.0, distribution[:percentages]['disabled']
    assert_equal 40.0, distribution[:percentages]['enabled']
    assert_equal 40.0, distribution[:percentages]['canary']
  end
end
