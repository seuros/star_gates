# frozen_string_literal: true

require 'test_helper'
require 'json'

class TestLLMIntrospection < Minitest::Test
  def setup
    StarGates.reset!

    # Create a comprehensive test scenario
    @payment_feature = StarGates::Feature.new(rollout: 25, group: :beta_users)
    @dashboard_feature = StarGates::Feature.new(rollout: 75)
    @experimental_feature = StarGates::Feature.new(rollout: 0)

    @payment_gate = StarGates::Gate.new(:payment_v2, feature: @payment_feature)
    @dashboard_gate = StarGates::Gate.new(:dashboard_redesign, feature: @dashboard_feature)
    @experimental_gate = StarGates::Gate.new(:experimental_ai, feature: @experimental_feature)

    StarGates.registry.register(:payment_v2, @payment_gate)
    StarGates.registry.register(:dashboard_redesign, @dashboard_gate)
    StarGates.registry.register(:experimental_ai, @experimental_gate)

    # Set different states and create some history
    @payment_feature.rollout_canary
    @dashboard_feature.enable
    @payment_feature.disable
    @payment_feature.enable
    # experimental feature stays disabled
  end

  def test_feature_level_llm_introspection
    # Complete feature introspection in LLM-friendly format
    introspection_data = @payment_feature.to_h

    # Should be easily parseable by LLM
    assert introspection_data[:name]
    assert introspection_data[:class]
    assert introspection_data[:status]
    assert introspection_data[:stats]
    assert introspection_data[:configuration]
    assert introspection_data[:summary]
    assert introspection_data[:introspected_at]

    # Test serialization to JSON (common LLM format)
    json_data = JSON.generate(introspection_data)
    assert json_data.include?('Feature')
    assert json_data.include?('enabled')

    # Parse back to ensure it's valid JSON
    parsed = JSON.parse(json_data)
    assert_equal introspection_data[:name], parsed['name']
  end

  def test_transition_history_llm_format
    history = @payment_feature.transition_history

    # Should provide clear transition narrative
    assert_equal 'Feature', history[:feature_name]
    assert_equal 3, history[:total_transitions]
    assert_equal 3, history[:transitions].size

    # Transitions should be in reverse chronological order
    transitions = history[:transitions]
    assert_equal :disabled, transitions[0][:from_state]
    assert_equal :enabled, transitions[0][:to_state]
    assert_equal :enable, transitions[0][:event]

    # Each transition should have LLM-friendly metadata
    transitions.each do |transition|
      assert transition[:timestamp]
      assert transition[:feature_name]
      assert transition[:feature_class]
      assert transition[:from_state]
      assert transition[:to_state]
      assert transition[:event]
      assert transition[:duration_since]
    end
  end

  def test_system_level_llm_introspection
    # System-wide view for LLM analysis
    overview = StarGates.feature_overview

    # Should provide high-level system understanding
    assert_equal 3, overview[:total_gates]
    assert_equal 3, overview[:gates].size

    # Summary statistics for quick LLM comprehension
    summary = overview[:summary]
    assert_equal 3, summary[:total_features]
    assert_equal 1, summary[:by_status]['disabled']
    assert_equal 2, summary[:by_status]['enabled']
    assert_equal 0, (summary[:by_status]['canary'] || 0)

    # Each gate should have rich introspection data
    payment_gate = overview[:gates][:payment_v2]
    assert_equal :payment_v2, payment_gate[:name]
    assert payment_gate[:feature]
    assert_equal 'enabled', payment_gate[:feature][:status]
    assert payment_gate[:feature][:stats]
    assert payment_gate[:feature][:configuration]
    assert payment_gate[:feature][:summary]
  end

  def test_rollout_statistics_llm_analysis
    stats = StarGates.rollout_statistics

    # Should provide clear rollout insights
    assert_equal 3, stats[:total_gates]
    assert_equal 1, stats[:features_by_status]['disabled']
    assert_equal 2, stats[:features_by_status]['enabled']
    assert_equal 0, stats[:features_by_status]['canary']

    # Rollout distribution for understanding feature spread
    assert_equal 0, stats[:average_rollout] # No canary features
    assert_equal({}, stats[:rollout_distribution]) # No canary features

    # Timestamp for LLM to understand data freshness
    assert stats[:generated_at]
  end

  def test_recent_transitions_llm_narrative
    transitions = StarGates.recent_transitions

    # Should provide clear transition timeline
    assert_equal 4, transitions[:total_found]
    assert_equal 4, transitions[:transitions].size

    # Each transition should tell a story
    transitions[:transitions].each do |transition|
      assert transition[:timestamp]
      assert transition[:feature_name]
      assert transition[:feature_class]
      assert transition[:from_state]
      assert transition[:to_state]
      assert transition[:event]
      assert transition[:duration_since]
    end

    # Should be in reverse chronological order for narrative flow
    timestamps = transitions[:transitions].map { |t| t[:timestamp] }
    assert_equal timestamps.sort.reverse, timestamps
  end

  def test_user_simulation_llm_debugging
    # Test user scenarios for LLM troubleshooting
    beta_user = MockUser.new(id: 123, groups: [:beta_users])
    regular_user = MockUser.new(id: 456, groups: [:regular])

    # Beta user simulation
    beta_simulation = @payment_feature.simulate_for_user(
      user_id: beta_user.id,
      user_groups: beta_user.groups
    )

    assert_equal 123, beta_simulation[:user_id]
    assert_equal [:beta_users], beta_simulation[:user_groups]
    assert beta_simulation[:eligible]
    assert beta_simulation[:reason]
    assert beta_simulation[:ui_component]
    assert_equal 'enabled', beta_simulation[:feature_status]

    # Regular user simulation
    regular_simulation = @payment_feature.simulate_for_user(
      user_id: regular_user.id,
      user_groups: regular_user.groups
    )

    assert_equal 456, regular_simulation[:user_id]
    assert_equal [:regular], regular_simulation[:user_groups]
    assert regular_simulation[:eligible] # Feature is enabled for all
    assert regular_simulation[:reason]
    assert regular_simulation[:ui_component]
    assert_equal 'enabled', regular_simulation[:feature_status]
  end

  def test_eligibility_debugging_llm_insights
    # Detailed debugging for LLM analysis
    user = MockUser.new(id: 500, groups: [:regular])

    debug_info = @payment_feature.eligibility_debug(user: user)

    # Should provide clear debugging narrative
    assert_equal 500, debug_info[:user_id]
    assert_equal 'enabled', debug_info[:feature_status]
    assert_equal 25, debug_info[:rollout_percentage]
    assert_equal :beta_users, debug_info[:group_matcher]
    assert debug_info[:eligible]
    assert_equal 'Feature is fully enabled', debug_info[:reason]
  end

  def test_complete_llm_introspection_report
    # Generate a complete report that an LLM could use to understand the system
    report = {
      timestamp: Time.now,
      system_overview: StarGates.feature_overview,
      rollout_statistics: StarGates.rollout_statistics,
      state_distribution: StarGates.state_distribution,
      recent_transitions: StarGates.recent_transitions,
      features: {
        payment_v2: @payment_feature.to_h,
        dashboard_redesign: @dashboard_feature.to_h,
        experimental_ai: @experimental_feature.to_h
      }
    }

    # Should be comprehensive and structured
    assert report[:timestamp]
    assert report[:system_overview]
    assert report[:rollout_statistics]
    assert report[:state_distribution]
    assert report[:recent_transitions]
    assert report[:features]

    # Test JSON serialization for LLM consumption
    json_report = JSON.generate(report)
    assert json_report.size > 1000 # Should be substantial

    # Should be valid JSON that can be parsed
    parsed_report = JSON.parse(json_report)
    assert parsed_report['system_overview']
    assert parsed_report['features']
  end
end
