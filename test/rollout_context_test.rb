# frozen_string_literal: true

require 'test_helper'

class RolloutContextTest < Minitest::Test
  def setup
    super
    @feature = StarGates::Feature.new(rollout: 50)
    @feature.rollout_canary
  end

  def test_string_and_integer_keys_use_the_same_bucket
    assert_equal @feature.eligibility_debug(key: 42)[:hash_modulo],
                 @feature.eligibility_debug(key: '42')[:hash_modulo]
  end

  def test_zero_is_a_valid_key
    debug = @feature.eligibility_debug(key: 0)

    assert_equal 0, debug[:key]
    assert_equal Zlib.crc32('0') % 100, debug[:hash_modulo]
  end

  def test_missing_key_is_ineligible_for_partial_rollout
    refute @feature.enabled_for?
    refute @feature.enabled_for?(key: nil)
    assert_equal 'No rollout key found in context', @feature.eligibility_debug[:reason]
  end

  def test_objects_are_not_implicitly_converted_to_keys
    [Object.new, [], {}, true, false].each do |key|
      refute @feature.enabled_for?(key: key)
      assert_nil @feature.eligibility_debug(key: key)[:key]
    end
  end

  def test_only_explicit_key_drives_partial_rollout
    refute @feature.enabled_for?(id: 'resident-123')
    refute @feature.enabled_for?(account_id: 'resident-123')
  end

  def test_symbol_groups_are_explicit_context
    feature = StarGates::Feature.new(group: :premium)
    feature.rollout_canary

    assert feature.enabled_for?(key: 'account:1', groups: [:premium])
    refute feature.enabled_for?(key: 'account:2', groups: [:regular])
    refute feature.enabled_for?(key: 'account:1')
    refute feature.enabled_for?(key: 'account:1', groups: nil)
  end

  def test_group_predicate_receives_the_full_context
    feature = StarGates::Feature.new(group: ->(context) { context[:region] == 'eu' && context[:enabled] })
    feature.rollout_canary

    assert feature.enabled_for?(key: 'device:1', region: 'eu', enabled: true)
    refute feature.enabled_for?(key: 'device:2', region: 'us', enabled: true)
    refute feature.enabled_for?(key: 'device:1', region: 'eu', enabled: false)
  end

  def test_debugging_uses_the_same_context_as_group_evaluation
    feature = StarGates::Feature.new(group: ->(context) { context[:region] == 'eu' })
    feature.rollout_canary

    debug = feature.eligibility_debug(key: 'device:1', region: 'eu')

    assert_equal 'device:1', debug[:key]
    assert debug[:eligible]
    assert debug[:group_match]
  end

  def test_simulation_uses_explicit_key_and_groups
    feature = StarGates::Feature.new(group: :premium)
    feature.rollout_canary

    result = feature.simulate(key: 'account:1', groups: [:premium])

    assert_equal 'account:1', result[:key]
    assert_equal [:premium], result[:groups]
    assert result[:eligible]
    assert_equal 'feature_component', result[:ui_component]
  end

  def test_simulation_forwards_custom_context
    feature = StarGates::Feature.new(group: ->(context) { context[:region] == 'eu' })
    feature.rollout_canary

    assert feature.simulate(key: 'device:1', region: 'eu')[:eligible]
    refute feature.simulate(key: 'device:1', region: 'us')[:eligible]
  end

  def test_scenarios_match_actual_key_eligibility
    keys = ['account:1', 'device:2', 0, 42]
    scenarios = @feature.test_rollout_scenarios([25, 50, 75], sample_keys: keys)

    scenarios.each do |percentage, scenario|
      feature = StarGates::Feature.new(rollout: percentage)
      feature.rollout_canary
      eligible = keys.count { |key| feature.enabled_for?(key: key) }

      assert_equal keys.size, scenario[:sample_size]
      assert_equal eligible, scenario[:eligible_keys]
    end
  end

  def test_gate_forwards_key_and_execution_context
    gate = StarGates::Gate.new(
      :preview,
      feature: @feature,
      run_block: ->(context) { [context[:key], context[:amount]] },
      fallback_block: -> { :unavailable }
    )

    assert_equal ['resident-123', 10], gate.call(key: 'resident-123', amount: 10)
    assert_equal :unavailable, gate.call(key: 'account-42', amount: 10)
    assert_equal :unavailable, gate.call(amount: 10)
  end

  def test_gate_group_predicate_receives_execution_context
    feature = StarGates::Feature.new(group: ->(context) { context[:region] == 'eu' })
    feature.rollout_canary
    gate = StarGates::Gate.new(
      :regional_preview,
      feature: feature,
      run_block: -> { :available },
      fallback_block: -> { :unavailable }
    )

    assert_equal :available, gate.call(key: 'device:1', region: 'eu')
    assert_equal :unavailable, gate.call(key: 'device:2', region: 'us')
  end
end
