# frozen_string_literal: true

require 'test_helper'

class TestIntrospection < Minitest::Test
  def setup
    @feature = StarGates::Feature.new(rollout: 25, group: :beta_users)
    @user = MockUser.new(id: 123, groups: [:beta_users])
    @context = { user: @user }
  end

  def test_stats_method
    stats = @feature.stats

    assert_equal 'StarGates::Feature', stats[:name]
    assert_equal 'disabled', stats[:status]
    assert_equal 25, stats[:rollout_percentage]
    assert stats[:group_matcher]
    assert stats[:created_at]
    assert_equal 0, stats[:total_transitions]
  end

  def test_configuration_method
    config = @feature.configuration

    assert_equal 25, config[:rollout_percentage]
    assert_equal :beta_users, config[:group_matcher]
    assert config[:feature_config]
    assert config[:default_config]
    assert config[:state_machine_config]
  end

  def test_summary_method_disabled_state
    summary = @feature.summary
    assert_includes summary, 'DISABLED'
    assert_includes summary, 'No users have access'
  end

  def test_summary_method_enabled_state
    @feature.enable
    summary = @feature.summary
    assert_includes summary, 'ENABLED'
    assert_includes summary, '100% rollout'
  end

  def test_summary_method_canary_state
    @feature.rollout_canary
    summary = @feature.summary
    assert_includes summary, 'CANARY'
    assert_includes summary, '25%'
  end

  def test_to_h_method
    hash = @feature.to_h

    assert hash[:name]
    assert_equal 'StarGates::Feature', hash[:class]
    assert_equal 'disabled', hash[:status]
    assert hash[:stats]
    assert hash[:configuration]
    assert hash[:summary]
    assert hash[:introspected_at]
  end

  def test_simulate_for_user
    @feature.rollout_canary

    simulation = @feature.simulate_for_user(user_id: 123, user_groups: [:beta_users])

    assert_equal 123, simulation[:user_id]
    assert_equal [:beta_users], simulation[:user_groups]
    assert simulation.key?(:eligible)
    assert simulation[:reason]
    assert simulation[:ui_component]
    assert_equal 'canary', simulation[:feature_status]
  end

  def test_eligibility_debug_disabled_feature
    debug = @feature.eligibility_debug(user: @user)

    assert_equal 123, debug[:user_id]
    assert_equal 'disabled', debug[:feature_status]
    assert_equal 'Feature is disabled', debug[:reason]
    refute debug[:eligible]
  end

  def test_eligibility_debug_enabled_feature
    @feature.enable
    debug = @feature.eligibility_debug(user: @user)

    assert_equal 'enabled', debug[:feature_status]
    assert_equal 'Feature is fully enabled', debug[:reason]
    assert debug[:eligible]
  end

  def test_eligibility_debug_canary_with_group
    @feature.rollout_canary
    debug = @feature.eligibility_debug(user: @user)

    assert_equal 'canary', debug[:feature_status]
    assert debug.key?(:group_match)
    assert debug[:reason]
  end

  def test_eligibility_debug_canary_with_percentage
    feature = StarGates::Feature.new(rollout: 50)
    feature.rollout_canary

    debug = feature.eligibility_debug(user: @user)

    assert_equal 'canary', debug[:feature_status]
    assert debug.key?(:user_hash)
    assert debug.key?(:hash_modulo)
    assert debug[:reason].include?('hash')
  end

  def test_test_rollout_scenarios
    scenarios = @feature.test_rollout_scenarios([10, 25, 50, 100])

    assert_equal 4, scenarios.size
    assert scenarios[10]
    assert scenarios[25]
    assert scenarios[50]
    assert scenarios[100]

    scenarios.each do |percentage, data|
      assert_equal percentage, data[:percentage]
      assert data[:sample_size].positive?
      assert data.key?(:eligible_users)
      assert data.key?(:estimated_percentage)
    end
  end

  def test_state_machine_config
    config = @feature.send(:state_machine_config)

    assert_equal :disabled, config[:initial_state]
    assert_includes config[:states], :disabled
    assert_includes config[:states], :enabled
    assert_includes config[:states], :canary
    assert_includes config[:events], :enable
    assert_includes config[:events], :disable
    assert_includes config[:events], :rollout_canary
  end

  def test_group_matcher_info_symbol
    info = @feature.send(:group_matcher_info)

    assert_equal 'symbol', info[:type]
    assert_equal :beta_users, info[:value]
  end

  def test_group_matcher_info_proc
    feature = StarGates::Feature.new(group: ->(user) { user.id.even? })
    info = feature.send(:group_matcher_info)

    assert_equal 'proc', info[:type]
    assert_equal '<Proc>', info[:value]
  end

  def test_group_matcher_info_nil
    feature = StarGates::Feature.new
    info = feature.send(:group_matcher_info)

    assert_nil info
  end
end
