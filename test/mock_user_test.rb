# frozen_string_literal: true

require 'test_helper'

# Feature mock-user behavior tests.
class MockUserTest < Minitest::Test
  # ============================================================================
  # Data.define
  # ============================================================================

  def test_data_define_mock_user_is_immutable
    mock_user = StarGates::Feature::MockUser.new(id: 123, groups: [:admin])

    assert_equal 123, mock_user.id
    assert_equal [:admin], mock_user.groups

    # Data.define creates immutable structs
    assert_raises(FrozenError, NoMethodError) do
      mock_user.id = 456
    end
  end

  def test_data_define_mock_user_equality
    user1 = StarGates::Feature::MockUser.new(id: 123, groups: [:admin])
    user2 = StarGates::Feature::MockUser.new(id: 123, groups: [:admin])
    user3 = StarGates::Feature::MockUser.new(id: 456, groups: [:user])

    # Data.define provides value equality
    assert_equal user1, user2, 'Same values should be equal'
    refute_equal user1, user3, 'Different values should not be equal'
  end

  def test_data_define_mock_user_hash_consistency
    user1 = StarGates::Feature::MockUser.new(id: 123, groups: [:admin])
    user2 = StarGates::Feature::MockUser.new(id: 123, groups: [:admin])

    # Data.define provides consistent hashing
    assert_equal user1.hash, user2.hash, 'Equal objects should have same hash'

    # Can be used as hash keys
    hash = { user1 => 'value1' }
    assert_equal 'value1', hash[user2], 'Should work as hash key'
  end

  def test_data_define_mock_user_pattern_matching
    user = StarGates::Feature::MockUser.new(id: 123, groups: %i[admin beta])

    # Data.define supports pattern matching.
    result = case user
             in { id: Integer => user_id, groups: Array => groups } if groups.include?(:admin)
               "Admin user #{user_id}"
             in { id: Integer => user_id, groups: Array }
               "Regular user #{user_id}"
             else
               'Unknown'
             end

    assert_equal 'Admin user 123', result
  end

  def test_data_define_mock_user_with_feature_simulation
    feature = StarGates::Feature.new(rollout: 50, group: :premium)
    feature.rollout_canary

    # Test with various user configurations
    premium_user = { user_id: 1, user_groups: [:premium] }
    regular_user = { user_id: 2, user_groups: [:regular] }

    premium_result = feature.simulate_for_user(**premium_user)
    regular_result = feature.simulate_for_user(**regular_user)

    # Premium users should be eligible due to group targeting
    assert premium_result[:eligible], 'Premium user should be eligible'
    refute regular_result[:eligible], 'Regular user should not be eligible'
  end

  def test_data_define_mock_user_serialization
    user = StarGates::Feature::MockUser.new(id: 123, groups: %i[admin beta])

    # Data.define provides to_h
    hash = user.to_h

    assert_equal({ id: 123, groups: %i[admin beta] }, hash)

    # Can recreate from hash
    user2 = StarGates::Feature::MockUser.new(**hash)
    assert_equal user, user2
  end

  # ============================================================================
  # Performance characteristics
  # ============================================================================

  def test_data_define_construction_performance
    require 'benchmark'

    iterations = 10_000

    data_define_time = Benchmark.realtime do
      iterations.times do |i|
        user = StarGates::Feature::MockUser.new(id: i, groups: [:admin])
        _ = user.id
        _ = user.groups
      end
    end

    puts "\nData.define performance: #{(data_define_time * 1000).round(2)}ms for #{iterations} iterations"

    assert data_define_time < 0.1, 'Data.define should be fast'
  end

  def test_data_define_memory_efficiency
    require 'objspace'

    user = StarGates::Feature::MockUser.new(id: 123, groups: %i[admin beta])

    memsize = ObjectSpace.memsize_of(user)

    # Should be relatively small (< 200 bytes typically)
    assert memsize < 500, "Data.define should be memory efficient, got #{memsize} bytes"
  end

  # ============================================================================
  # Integration with feature system
  # ============================================================================

  def test_eligibility_debug_with_data_define_user
    feature = StarGates::Feature.new(rollout: 50)
    feature.rollout_canary

    user = StarGates::Feature::MockUser.new(id: 12_345, groups: [:beta])
    debug_info = feature.eligibility_debug(user: user)

    assert_equal 12_345, debug_info[:user_id]
    assert_equal 'canary', debug_info[:feature_status]
    assert_includes [true, false], debug_info[:eligible]
    assert debug_info[:reason], 'Should provide eligibility reason'
  end

  def test_concurrent_mock_user_creation
    # Data.define structs are thread-safe for creation
    threads = 10.times.map do |i|
      Thread.new do
        100.times do |j|
          user = StarGates::Feature::MockUser.new(
            id: (i * 100) + j,
            groups: %i[admin beta]
          )
          assert_equal (i * 100) + j, user.id
        end
      end
    end

    threads.each(&:join)
  end

  # ============================================================================
  # Keyword arguments
  # ============================================================================

  def test_data_define_with_keyword_arguments
    user = StarGates::Feature::MockUser.new(id: 999, groups: [:owner])

    feature = StarGates::Feature.new(group: ->(u) { u.groups.include?(:owner) })
    feature.rollout_canary

    assert feature.enabled_for?(user: user), 'Owner should be enabled'
  end
end
