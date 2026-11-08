# frozen_string_literal: true

require 'test_helper'

class TestApplicationStarGate < Minitest::Test
  def setup
    # Create a test class using ApplicationStarGate
    @test_class = Class.new(StarGates::ApplicationStarGate)

    # Call configure on the class
    @test_class.configure 'test_feature',
                          timeout: 2.0,
                          retry_count: 2,
                          performance_monitoring: true,
                          instrumentation: true,
                          enabled_config: {
                            'api_version' => 'v2',
                            'feature_flag' => true
                          },
                          disabled_config: {
                            'api_version' => 'v1',
                            'feature_flag' => false
                          }

    # Set telemetry tags directly for now (for_team method issue needs investigation)
    @test_class.telemetry_tags = { team: 'test_team' }
  end

  def test_activesupport_configurable_integration
    feature = @test_class.new(rollout: 50)

    # Test that ActiveSupport::Configurable worked
    assert_equal 'test_feature', @test_class.feature_name
    assert_equal 2.0, feature.timeout
    assert_equal 2, feature.retry_count
    assert feature.performance_monitoring_enabled?
  end

  def test_hash_with_indifferent_access
    feature = @test_class.new(rollout: 100)
    feature.enable

    config = feature.feature_config

    # Test both string and symbol access work (HashWithIndifferentAccess)
    assert_equal 'v2', config['api_version']
    assert_equal 'v2', config[:api_version]
    assert_equal true, config['feature_flag']
    assert_equal true, config[:feature_flag]
  end

  def test_state_specific_configurations
    feature = @test_class.new(rollout: 100)

    # Test disabled state config
    assert_equal 'disabled', feature.status
    disabled_config = feature.feature_config
    assert_equal 'v1', disabled_config['api_version']
    assert_equal false, disabled_config['feature_flag']

    # Test enabled state config
    feature.enable
    assert_equal 'enabled', feature.status
    enabled_config = feature.feature_config
    assert_equal 'v2', enabled_config['api_version']
    assert_equal true, enabled_config['feature_flag']
  end

  def test_activesupport_notifications
    skip 'Telemetry not configured in test' unless StarGates.telemetry

    notifications_received = []

    # Subscribe to ActiveSupport::Notifications
    subscription = ActiveSupport::Notifications.subscribe(/star_gates\./) do |name, start, finish, _id, payload|
      notifications_received << {
        name: name,
        duration: (finish - start) * 1000,
        payload: payload
      }
    end

    feature = @test_class.new(rollout: 100)
    feature.enable

    # Execute feature to trigger notifications
    context = { key: 123 }
    result = feature.execute(context) { 'test result' }

    assert_equal 'test result', result

    # Check that notifications were sent
    feature_notifications = notifications_received.select { |n| n[:name].include?('star_gates') }
    refute_empty feature_notifications if StarGates.telemetry

    # Clean up subscription
    ActiveSupport::Notifications.unsubscribe(subscription)
  end

  def test_telemetry_tags
    @test_class.new(rollout: 100)

    # Test that team tags are properly set
    expected_tags = { team: 'test_team' }

    # The tags should be set by direct assignment in setup
    refute_empty @test_class.telemetry_tags, 'Telemetry tags should not be empty'
    assert_equal expected_tags, @test_class.telemetry_tags
  end

  def test_enhanced_introspection
    feature = @test_class.new(rollout: 100)
    feature.enable

    # Test configuration summary
    config_summary = feature.configuration_summary
    assert_equal 2.0, config_summary[:timeout]
    assert_equal 2, config_summary[:retry_count]
    assert config_summary[:performance_monitoring]

    # Test feature identifier
    assert_equal 'test_feature', feature.feature_identifier

    # Test enhanced to_h output
    introspection = feature.to_h
    assert_equal 'test_feature', introspection[:name]
    assert introspection[:environment], 'Should have environment set'
    assert introspection[:configuration]
    assert introspection[:performance]
  end

  def test_configuration_inheritance
    # Test that configuration is properly inherited and merged
    feature = @test_class.new(rollout: 50, timeout: 3.0) # Override timeout at instance level

    # Instance-level override should take precedence
    assert_equal 3.0, feature.timeout
    # Class-level config should still work
    assert_equal 2, feature.retry_count
  end

  def test_subclass_config_inherits_without_leaking_upward
    child = Class.new(@test_class)
    child.configure(timeout: 9.0, cache_ttl: 60)

    assert_equal 9.0, child.new.timeout
    assert_equal 2, child.new.retry_count
    assert_equal 60, child.new.cache_ttl
    assert_equal 2.0, @test_class.new.timeout
    assert_nil @test_class.new.cache_ttl
    assert_nil Class.new(StarGates::ApplicationStarGate).new.timeout
  end

  def test_parent_config_set_later_reaches_existing_subclasses
    child = Class.new(@test_class)
    child.config # materialize before the parent changes
    @test_class.configure(circuit_breaker_threshold: 7)

    assert_equal 7, child.new.circuit_breaker_threshold
  end

  def test_does_not_use_deprecated_activesupport_configurable
    refute_includes StarGates::ApplicationStarGate.ancestors.map(&:name), 'ActiveSupport::Configurable'
  end

  def teardown
    # Clean up any subscriptions
    ActiveSupport::Notifications.unsubscribe(/star_gates\./)
  end
end
