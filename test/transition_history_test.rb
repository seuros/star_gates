# frozen_string_literal: true

require 'test_helper'

class TestTransitionHistory < Minitest::Test
  def setup
    @feature = StarGates::Feature.new(rollout: 25, group: :beta_users)
  end

  def test_feature_initializes_with_empty_transition_history
    assert_equal 0, @feature.transition_count
    assert_kind_of Concurrent::Array, @feature.instance_variable_get(:@transition_history)
  end

  def test_transition_history_method_with_no_transitions
    history = @feature.transition_history

    assert_equal 'Feature', history[:feature_name]
    assert_equal 0, history[:total_transitions]
    assert_equal [], history[:transitions]
    assert_equal 10, history[:limit]
  end

  def test_state_duration_with_no_transitions
    assert_equal 'No transitions yet', @feature.send(:state_duration)
  end

  def test_transition_tracking_on_state_change
    initial_count = @feature.transition_count

    # Trigger a state transition
    @feature.rollout_canary

    # Should have recorded the transition
    assert_equal initial_count + 1, @feature.transition_count

    # Check the transition was recorded
    history = @feature.transition_history(limit: 1)
    assert_equal 1, history[:total_transitions]

    transition = history[:transitions].first
    assert_equal :disabled, transition[:from_state]
    assert_equal :canary, transition[:to_state]
    assert_equal :rollout_canary, transition[:event]
    assert transition[:timestamp]
    assert transition[:duration_since] >= 0
  end

  def test_multiple_state_transitions
    # Chain of state transitions
    @feature.rollout_canary   # disabled -> canary
    @feature.enable           # canary -> enabled
    @feature.disable          # enabled -> disabled
    @feature.enable           # disabled -> enabled

    assert_equal 4, @feature.transition_count

    history = @feature.transition_history
    assert_equal 4, history[:transitions].size

    # Check the transitions are in correct order (most recent first)
    transitions = history[:transitions]

    # Most recent: disabled -> enabled (enable)
    assert_equal :disabled, transitions[0][:from_state]
    assert_equal :enabled, transitions[0][:to_state]
    assert_equal :enable, transitions[0][:event]

    # Second most recent: enabled -> disabled (disable)
    assert_equal :enabled, transitions[1][:from_state]
    assert_equal :disabled, transitions[1][:to_state]
    assert_equal :disable, transitions[1][:event]

    # Third most recent: canary -> enabled (enable)
    assert_equal :canary, transitions[2][:from_state]
    assert_equal :enabled, transitions[2][:to_state]
    assert_equal :enable, transitions[2][:event]

    # Oldest: disabled -> canary (rollout_canary)
    assert_equal :disabled, transitions[3][:from_state]
    assert_equal :canary, transitions[3][:to_state]
    assert_equal :rollout_canary, transitions[3][:event]
  end

  def test_transition_history_includes_feature_metadata
    @feature.rollout_canary

    history = @feature.transition_history
    transition = history[:transitions].first

    assert_equal 'Feature', history[:feature_name] # Check the history's feature_name
    assert_equal 'StarGates::Feature', transition[:feature_class] if transition # Check transition metadata
    assert transition[:timestamp] if transition
    assert_kind_of Numeric, transition[:duration_since] if transition
  end

  def test_state_duration_after_transition
    @feature.rollout_canary

    # Should show time since last transition
    duration = @feature.send(:state_duration)
    refute_equal 'No transitions yet', duration
    assert duration.end_with?('s') # Should be seconds for a recent transition
  end

  def test_transition_history_limit
    # Make more transitions than the default limit
    15.times do |i|
      if i.even?
        @feature.enable
      else
        @feature.disable
      end
    end

    # Default limit should be 10
    history = @feature.transition_history
    assert_equal 10, history[:transitions].size
    assert_equal 15, history[:total_transitions]
    assert_equal 10, history[:limit]

    # Custom limit
    history = @feature.transition_history(limit: 5)
    assert_equal 5, history[:transitions].size
    assert_equal 15, history[:total_transitions]
    assert_equal 5, history[:limit]
  end

  def test_transition_history_memory_management
    # Make sure we don't accumulate too many transitions
    feature = StarGates::Feature.new

    # Make 100 transitions to test the 50-transition limit
    100.times do |i|
      if i.even?
        feature.enable
      else
        feature.disable
      end
    end

    # Should be capped at 50 transitions
    assert feature.transition_count <= 50

    # Most recent transitions should still be there
    history = feature.transition_history(limit: 2)
    assert_equal 2, history[:transitions].size
  end

  def test_transition_record_structure
    @feature.rollout_canary

    # Access the raw transition history
    raw_history = @feature.instance_variable_get(:@transition_history)
    transition = raw_history.first

    # Check the structure matches what record_transition creates
    assert transition[:timestamp]
    assert_equal :disabled, transition[:from_state]
    assert_equal :canary, transition[:to_state]
    assert_equal :rollout_canary, transition[:event]
    assert_equal 'Feature', transition[:feature_name]
    assert_equal 'StarGates::Feature', transition[:feature_class]
  end

  def test_concurrent_safety
    # Test that concurrent access doesn't break things
    threads = []

    10.times do
      threads << Thread.new do
        10.times do
          @feature.enable
          @feature.disable
        end
      end
    end

    threads.each(&:join)

    # Should have recorded all transitions without errors
    assert @feature.transition_count.positive?
    assert @feature.transition_count <= 200 # 10 threads * 10 iterations * 2 transitions each
  end
end
