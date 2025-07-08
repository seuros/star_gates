# frozen_string_literal: true

class DemoNotificationFeature < StarGates::ApplicationStarGate
  configure 'demo_notification_system',
            timeout: 2.0,
            retry_count: 2,
            performance_monitoring: true,
            instrumentation: true,
            enabled_config: {
              channels: %w[email sms push in_app],
              delivery_method: 'real_time',
              personalization: true,
              analytics_tracking: true
            },
            canary_config: {
              channels: %w[email push],
              delivery_method: 'batched',
              personalization: false,
              analytics_tracking: true
            },
            disabled_config: {
              channels: ['email'],
              delivery_method: 'legacy',
              personalization: false,
              analytics_tracking: false
            }

  for_team 'growth'

  def send_notification(user_id, message, notification_type = 'general')
    config = feature_config

    execute do
      {
        success: true,
        notification_id: "notif_#{Time.current.to_i}_#{rand(1000)}",
        user_id: user_id,
        message: message,
        type: notification_type,
        channels: config['channels'],
        delivery_method: config['delivery_method'],
        personalized: config['personalization'],
        tracking_enabled: config['analytics_tracking'],
        sent_at: Time.current
      }
    end
  end

  def get_available_channels
    config = feature_config
    config['channels'] || []
  end

  def supports_personalization?
    config = feature_config
    config['personalization'] || false
  end
end
