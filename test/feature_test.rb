# frozen_string_literal: true

require 'test_helper'

class TestFeature < Minitest::Test
  def test_feature_disabled_by_default
    feature = StarGates::Feature.new

    refute feature.enabled?
    refute feature.enabled_for?({})
  end

  def test_feature_percentage_rollout
    feature = StarGates::Feature.new(rollout: 50)

    # Feature is disabled by default, regardless of rollout
    refute feature.enabled?
    refute feature.enabled_for?({})

    # Once in canary mode, rollout percentage is used
    feature.rollout_canary
    assert feature.enabled?

    result1 = feature.enabled_for?(key: 1)
    result2 = feature.enabled_for?(key: 2)

    assert [true, false].include?(result1)
    assert [true, false].include?(result2)
  end

  def test_feature_full_rollout
    feature = StarGates::Feature.new(rollout: 100)

    # Feature is disabled by default, regardless of rollout
    refute feature.enabled?
    refute feature.enabled_for?({})

    # Once enabled, rollout percentage doesn't matter
    feature.enable
    assert feature.enabled?
    assert feature.enabled_for?(key: 1)
    assert feature.enabled_for?(key: 2)
  end

  def test_feature_group_targeting
    feature = StarGates::Feature.new(group: :beta)

    # Feature is disabled by default
    refute feature.enabled?

    # Once in canary mode, group targeting is used
    feature.rollout_canary
    assert feature.enabled?

    assert feature.enabled_for?(key: 1, groups: [:beta])
    refute feature.enabled_for?(key: 2, groups: [:regular])
  end

  def test_feature_proc_group_targeting
    feature = StarGates::Feature.new(group: ->(context) { context[:key].even? })

    # Feature is disabled by default
    refute feature.enabled?

    # Once in canary mode, proc group targeting is used
    feature.rollout_canary
    assert feature.enabled?

    assert feature.enabled_for?(key: 2)
    refute feature.enabled_for?(key: 1)
  end

  def test_feature_percentage_helper
    assert_equal 50, 50.percent
    assert_equal 25, 25.percent
  end

  def test_feature_string_rollout_parsing
    feature1 = StarGates::Feature.new(rollout: '50%')
    feature2 = StarGates::Feature.new(rollout: '75')

    # Features are disabled by default
    refute feature1.enabled?
    refute feature2.enabled?

    # Once enabled, they work
    feature1.enable
    feature2.enable
    assert feature1.enabled?
    assert feature2.enabled?
  end
end
