# frozen_string_literal: true

class Demo::NotificationsController < ApplicationController
  before_action :setup_notification_feature

  def send_notification
    user_id = params[:user_id] || 'user_123'
    message = params[:message] || 'Test notification message'
    notification_type = params[:type] || 'general'

    result = @notification_feature.send_notification(user_id, message, notification_type)

    render json: {
      notification_result: result,
      feature_status: @notification_feature.status,
      available_channels: @notification_feature.get_available_channels,
      personalization_enabled: @notification_feature.supports_personalization?
    }
  end

  def channels
    channels = @notification_feature.get_available_channels

    render json: {
      available_channels: channels,
      feature_status: @notification_feature.status,
      delivery_method: @notification_feature.feature_config['delivery_method'],
      personalization_enabled: @notification_feature.supports_personalization?
    }
  end

  private

  def setup_notification_feature
    @notification_feature = DemoNotificationFeature.new(rollout: 75)

    # Set state based on params for testing
    case params[:state]
    when 'enabled'
      @notification_feature.enable
    when 'canary'
      @notification_feature.rollout_canary
    when 'disabled'
      @notification_feature.disable
    end
  end
end
