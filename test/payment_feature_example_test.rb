# frozen_string_literal: true

require 'test_helper'
require_relative 'dummy/demos/payment_feature'

class PaymentFeatureExampleTest < ActiveSupport::TestCase
  def setup
    @user = MockUser.new(id: 123, groups: [:beta_users])
    @service = StarGates::Examples::PaymentService.new(
      user: @user,
      amount: 1000,
      currency: 'USD'
    )
  end

  def test_payment_feature_starts_disabled
    feature = StarGates::Examples::PaymentFeature.new(rollout: 25)
    assert_equal 'disabled', feature.status
    refute feature.enabled?
  end

  def test_payment_service_with_disabled_feature
    # Feature should be disabled by default
    result = @service.process_payment

    # Should fall back to legacy payment
    assert_equal 'v1', result[:api_version]
    assert result[:success]
  end

  def test_payment_service_ui_component_when_disabled
    assert_equal 'default_component', @service.payment_ui_component
  end

  def test_payment_service_config_when_disabled
    assert_equal 'v1', @service.payment_config(:api_version)
    assert_equal 10, @service.payment_config(:timeout)
  end

  def test_payment_service_with_enabled_feature
    # Enable the feature by accessing the internal instance
    payment_feature = @service.instance_variable_get(:@payment_feature)
    payment_feature.enable

    result = @service.process_payment

    # Should use new API
    assert_equal 'v2', result[:api_version]
    assert result[:success]
  end

  def test_payment_service_ui_component_when_enabled
    payment_feature = @service.instance_variable_get(:@payment_feature)
    payment_feature.enable

    assert_equal 'feature_component', @service.payment_ui_component
  end

  def test_payment_service_config_when_enabled
    payment_feature = @service.instance_variable_get(:@payment_feature)
    payment_feature.enable

    assert_equal 'v2', @service.payment_config(:api_version)
    assert_equal 30, @service.payment_config(:timeout)
  end

  def test_feature_status_reporting
    status = @service.feature_status

    assert_equal 'disabled', status[:status]
    refute status[:enabled]
    assert_equal 'default_component', status[:ui_component]
    assert_equal 'v1', status[:api_version]
  end

  def test_feature_status_reporting_when_enabled
    payment_feature = @service.instance_variable_get(:@payment_feature)
    payment_feature.enable

    status = @service.feature_status

    assert_equal 'enabled', status[:status]
    assert status[:enabled]
    assert_equal 'feature_component', status[:ui_component]
    assert_equal 'v2', status[:api_version]
  end

  def test_canary_rollout_behavior
    payment_feature = @service.instance_variable_get(:@payment_feature)
    payment_feature.rollout_canary

    # Mock rollout eligibility
    payment_feature.define_singleton_method(:eligible_for_rollout?) { |_context| true }

    result = @service.process_payment
    assert_equal 'v2', result[:api_version]

    # Test ineligible user
    payment_feature.define_singleton_method(:eligible_for_rollout?) { |_context| false }

    result = @service.process_payment
    assert_equal 'v1', result[:api_version]
  end
end
