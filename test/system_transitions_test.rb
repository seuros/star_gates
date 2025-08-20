# frozen_string_literal: true

require 'test_helper'

class TestSystemTransitions < Minitest::Test
  def setup
    StarGates.reset!

    # Create some gates with features
    @feature1 = StarGates::Feature.new(rollout: 25)
    @feature2 = StarGates::Feature.new(rollout: 50)
    @feature3 = StarGates::Feature.new(rollout: 0)

    @gate1 = StarGates::Gate.new(:payment_v2, feature: @feature1)
    @gate2 = StarGates::Gate.new(:dashboard_redesign, feature: @feature2)
    @gate3 = StarGates::Gate.new(:experimental_feature, feature: @feature3)

    StarGates.registry.register(:payment_v2, @gate1)
    StarGates.registry.register(:dashboard_redesign, @gate2)
    StarGates.registry.register(:experimental_feature, @gate3)
  end

  def test_recent_transitions_with_no_transitions
    transitions = StarGates.recent_transitions

    assert_equal [], transitions[:transitions]
    assert_equal 0, transitions[:total_found]
    assert_equal 10, transitions[:limit]
    assert transitions[:generated_at]
  end

  def test_recent_transitions_with_single_feature
    @feature1.rollout_canary

    transitions = StarGates.recent_transitions

    assert_equal 1, transitions[:transitions].size
    assert_equal 1, transitions[:total_found]

    transition = transitions[:transitions].first
    assert_equal 'Feature', transition[:feature_name]
    assert_equal 'StarGates::Feature', transition[:feature_class]
    assert_equal :disabled, transition[:from_state]
    assert_equal :canary, transition[:to_state]
    assert_equal :rollout_canary, transition[:event]
    assert transition[:timestamp]
    assert transition[:duration_since] >= 0
  end

  def test_recent_transitions_with_multiple_features
    # Make transitions on different features
    @feature1.rollout_canary
    sleep(0.01) # Ensure different timestamps
    @feature2.enable
    sleep(0.01)
    @feature3.rollout_canary

    transitions = StarGates.recent_transitions

    assert_equal 3, transitions[:transitions].size
    assert_equal 3, transitions[:total_found]

    # Should be sorted by timestamp descending (most recent first)
    transition_timestamps = transitions[:transitions].map { |t| t[:timestamp] }
    assert_equal transition_timestamps.sort.reverse, transition_timestamps
  end

  def test_recent_transitions_respects_limit
    # Make more transitions than default limit
    features = [@feature1, @feature2, @feature3]

    15.times do |i|
      feature = features[i % 3]
      if i.even?
        feature.enable
      else
        feature.disable
      end
      sleep(0.001) # Ensure different timestamps
    end

    # Debug: Check actual transition counts
    total_expected = @feature1.transition_count + @feature2.transition_count + @feature3.transition_count

    # Default limit
    transitions = StarGates.recent_transitions
    assert_equal 10, transitions[:transitions].size
    assert_equal total_expected, transitions[:total_found]
    assert_equal 10, transitions[:limit]

    # Custom limit
    transitions = StarGates.recent_transitions(limit: 5)
    assert_equal 5, transitions[:transitions].size
    assert_equal total_expected, transitions[:total_found]
    assert_equal 5, transitions[:limit]
  end

  def test_recent_transitions_cross_feature_ordering
    # Make interleaved transitions
    @feature1.enable
    @feature2.rollout_canary
    @feature1.disable
    @feature3.enable

    transitions = StarGates.recent_transitions

    # Should get all 4 transitions in chronological order (newest first)
    assert_equal 4, transitions[:transitions].size

    # The most recent should be feature3 enable
    most_recent = transitions[:transitions].first
    assert_equal :disabled, most_recent[:from_state]
    assert_equal :enabled, most_recent[:to_state]
    assert_equal :enable, most_recent[:event]
  end

  def test_recent_transitions_with_empty_registry
    StarGates.reset!

    transitions = StarGates.recent_transitions

    assert_equal [], transitions[:transitions]
    assert_equal 0, transitions[:total_found]
  end

  def test_recent_transitions_feature_metadata_accuracy
    @feature1.rollout_canary
    @feature2.enable

    transitions = StarGates.recent_transitions

    # Check that each transition has correct feature metadata
    transitions[:transitions].each do |transition|
      assert transition[:feature_name]
      assert_equal 'StarGates::Feature', transition[:feature_class]
      assert %i[disabled enabled canary].include?(transition[:from_state])
      assert %i[disabled enabled canary].include?(transition[:to_state])
      assert %i[enable disable rollout_canary].include?(transition[:event])
    end
  end

  def test_recent_transitions_thread_safety
    # Test concurrent transitions across multiple features
    threads = []

    5.times do
      threads << Thread.new do
        [@feature1, @feature2, @feature3].each do |feature|
          3.times do
            feature.enable
            feature.disable
          end
        end
      end
    end

    threads.each(&:join)

    transitions = StarGates.recent_transitions(limit: 100)

    # Should have captured many transitions without errors
    assert transitions[:total_found].positive?
    assert(transitions[:transitions].all? { |t| t[:timestamp] })
    assert(transitions[:transitions].all? { |t| t[:feature_name] })
  end

  def test_system_introspection_integration
    # Make some transitions
    @feature1.rollout_canary
    @feature2.enable
    @feature1.enable

    # Check that stats are updated properly
    [@feature1, @feature2].each do |feature|
      stats = feature.stats
      assert stats[:total_transitions].positive?
      refute_equal 'No transitions yet', feature.send(:state_duration)
    end

    # Check system-level view
    overview = StarGates.feature_overview
    overview[:gates].each_value do |gate_info|
      feature_stats = gate_info[:feature][:stats]
      # Features that had transitions should show them
      if %w[payment_v2 dashboard_redesign].include?(gate_info[:name].to_s)
        assert feature_stats[:total_transitions].positive?
      end
    end
  end
end
