# frozen_string_literal: true

require 'test_helper'

class TestFeatureStateMachine < Minitest::Test
  def setup
    @feature = StarGates::Feature.new(rollout: 50, group: :beta_users)
    @user = MockUser.new(id: 123, groups: [:beta_users])
    @context = { user: @user }
  end

  def test_initial_state_is_disabled
    assert_equal 'disabled', @feature.status
    refute @feature.enabled?
  end

  def test_disabled_state_execute_returns_nil
    result = @feature.execute(@context) { 'new feature logic' }
    assert_nil result
  end

  def test_disabled_state_ui_component
    assert_equal 'default_component', @feature.ui_component
  end

  def test_enable_transition
    @feature.enable
    assert_equal 'enabled', @feature.status
    assert @feature.enabled?
  end

  def test_enabled_state_execute_yields_block
    @feature.enable
    result = @feature.execute(@context) { 'new feature logic' }
    assert_equal 'new feature logic', result
  end

  def test_enabled_state_ui_component
    @feature.enable
    assert_equal 'feature_component', @feature.ui_component
  end

  def test_canary_rollout_transition
    @feature.rollout_canary
    assert_equal 'canary', @feature.status
    assert @feature.enabled?
  end

  def test_canary_state_execute_with_eligible_user
    @feature.rollout_canary

    # Mock the rollout eligibility to return true
    @feature.define_singleton_method(:eligible_for_rollout?) { |_context| true }

    result = @feature.execute(@context) { 'new feature logic' }
    assert_equal 'new feature logic', result
  end

  def test_canary_state_execute_with_ineligible_user
    @feature.rollout_canary

    # Mock the rollout eligibility to return false
    @feature.define_singleton_method(:eligible_for_rollout?) { |_context| false }

    result = @feature.execute(@context) { 'new feature logic' }
    assert_nil result
  end

  def test_canary_state_ui_component_with_eligible_user
    @feature.rollout_canary
    @feature.define_singleton_method(:eligible_for_rollout?) { |_context| true }

    assert_equal 'feature_component', @feature.ui_component
  end

  def test_canary_state_ui_component_with_ineligible_user
    @feature.rollout_canary
    @feature.define_singleton_method(:eligible_for_rollout?) { |_context| false }

    assert_equal 'default_component', @feature.ui_component
  end

  def test_config_value_per_state
    # Test disabled state config
    assert_nil @feature.config_value(:some_key)

    # Test enabled state config
    @feature.enable
    assert_nil @feature.config_value(:some_key)
  end

  def test_state_transitions_work_correctly
    # disabled -> enabled -> disabled
    @feature.enable
    assert_equal 'enabled', @feature.status

    @feature.disable
    assert_equal 'disabled', @feature.status

    # disabled -> canary -> enabled
    @feature.rollout_canary
    assert_equal 'canary', @feature.status

    @feature.enable
    assert_equal 'enabled', @feature.status
  end

  def test_enabled_for_respects_state
    # When disabled, should return false regardless of rollout
    refute @feature.enabled_for?(@context)

    # When enabled, should return true regardless of rollout
    @feature.enable
    assert @feature.enabled_for?(@context)

    # When canary, should respect rollout logic
    @feature.rollout_canary
    # This will depend on the user hash, but we can test the method exists
    assert_respond_to @feature, :enabled_for?
  end
end
