# frozen_string_literal: true

# Configure StarGates for the dummy Rails application
Rails.application.config.after_initialize do
  # Subscribe to StarGates notifications for monitoring
  ActiveSupport::Notifications.subscribe(/star_gates\./) do |name, start, finish, _id, payload|
    duration = (finish - start) * 1000

    Rails.logger.info "[StarGates] Event: #{name}"
    Rails.logger.info "[StarGates] Duration: #{duration.round(2)}ms"
    Rails.logger.info "[StarGates] Payload: #{payload.inspect}"
    Rails.logger.info '[StarGates] ---'
  end

  # Define some example feature flags using the DSL (simplified - no circuits for now)
  StarGates.define do
    gate :legacy_payment do
      feature rollout: 0, group: :beta_users
    end

    gate :new_dashboard do
      feature rollout: 25, group: :premium_users
    end

    gate :experimental_ai do
      feature rollout: 5
    end

    gate :notification_system do
      feature rollout: 80
    end
  end

  Rails.logger.info "[StarGates] Initialized with #{StarGates.gates.size} feature gates"
  Rails.logger.info "[StarGates] Available gates: #{StarGates.gates.join(', ')}"

  # Log feature overview
  overview = StarGates.feature_overview
  Rails.logger.info "[StarGates] Total features: #{overview[:summary][:total_features]}"
  Rails.logger.info "[StarGates] Features by status: #{overview[:summary][:by_status]}"
end
