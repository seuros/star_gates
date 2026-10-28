# frozen_string_literal: true

require_relative '../../../lib/star_gates'

module StarGates
  module Examples
    # Example PaymentFeature class demonstrating state-specific methods
    class PaymentFeature < StarGates::Feature
      def initialize(rollout: 0, group: nil)
        super
        # Set up feature-specific configuration
        @feature_config = {
          api_version: 'v2',
          timeout: 30,
          retry_count: 3
        }

        @default_config = {
          api_version: 'v1',
          timeout: 10,
          retry_count: 1
        }
      end

      attr_reader :feature_config, :default_config
    end

    # Example service class using the PaymentFeature
    class PaymentService
      def initialize(user:, amount:, currency: 'USD')
        @user = user
        @amount = amount
        @currency = currency
        @payment_feature = PaymentFeature.new(rollout: 25, group: :beta_users)
      end

      def process_payment
        context = { user: @user, amount: @amount, currency: @currency }

        # Execute the feature with context
        result = @payment_feature.execute(context) do
          # This block contains the new payment logic
          process_stripe_v2_payment
        end

        # If result is nil, the feature was disabled and no new logic ran
        if result.nil?
          # Fall back to legacy payment processing
          process_legacy_payment
        else
          result
        end
      end

      def payment_ui_component
        context = { user: @user, amount: @amount, currency: @currency }
        @payment_feature.ui_component(context)
      end

      def payment_config(key)
        context = { user: @user, amount: @amount, currency: @currency }
        @payment_feature.config_value(key, context)
      end

      def feature_status
        {
          status: @payment_feature.status,
          enabled: @payment_feature.enabled?,
          ui_component: payment_ui_component,
          api_version: payment_config(:api_version)
        }
      end

      private

      def process_stripe_v2_payment
        logger&.info 'Processing with Stripe API v2'
        # Simulate new Stripe API v2 logic
        { success: true, transaction_id: generate_transaction_id, api_version: 'v2' }
      end

      def process_legacy_payment
        logger&.info 'Processing with legacy payment system'
        # Simulate legacy payment logic
        { success: true, transaction_id: generate_transaction_id, api_version: 'v1' }
      end

      def logger
        @logger ||= defined?(Rails) ? Rails.logger : nil
      end

      def generate_transaction_id
        # Simple transaction ID generation for testing
        "txn_#{Time.now.to_i}_#{rand(1000)}"
      end
    end
  end
end

# Demo script when file is run directly
if __FILE__ == $PROGRAM_NAME
  puts '💳 Payment Feature Demo'
  puts '=' * 30

  # Create test users
  beta_user = StarGates::Feature::MockUser.new(id: 123, groups: [:beta_users])
  regular_user = StarGates::Feature::MockUser.new(id: 456, groups: [:regular])

  # Create payment services
  beta_payment = StarGates::Examples::PaymentService.new(
    user: beta_user,
    amount: 100.00,
    currency: 'USD'
  )

  regular_payment = StarGates::Examples::PaymentService.new(
    user: regular_user,
    amount: 50.00,
    currency: 'USD'
  )

  puts "\n🧪 Testing different feature states..."

  # Test disabled state (default)
  puts "\n📊 DISABLED State:"
  puts "Beta user status: #{beta_payment.feature_status}"
  puts "Regular user status: #{regular_payment.feature_status}"

  # Move to canary state
  beta_payment.instance_variable_get(:@payment_feature).rollout_canary
  regular_payment.instance_variable_get(:@payment_feature).rollout_canary

  puts "\n📊 CANARY State (25% rollout, beta_users group):"
  puts "Beta user status: #{beta_payment.feature_status}"
  puts "Regular user status: #{regular_payment.feature_status}"

  # Process payments
  puts "\n💰 Processing payments..."
  beta_result = beta_payment.process_payment
  regular_result = regular_payment.process_payment

  puts "Beta user payment: #{beta_result}"
  puts "Regular user payment: #{regular_result}"

  # Move to enabled state
  beta_payment.instance_variable_get(:@payment_feature).enable

  puts "\n📊 ENABLED State:"
  puts "Beta user status: #{beta_payment.feature_status}"

  # Process payment with enabled feature
  puts "\n💰 Processing payment with enabled feature..."
  enabled_result = beta_payment.process_payment
  puts "Enabled payment: #{enabled_result}"

  # Show introspection data
  feature = beta_payment.instance_variable_get(:@payment_feature)
  puts "\n🔍 Feature Introspection:"
  puts "Transition count: #{feature.transition_count}"
  puts "Current state: #{feature.status}"
  puts "Summary: #{feature.summary}"

  if feature.transition_count.positive?
    puts "\nTransition history:"
    feature.transition_history(limit: 5)[:transitions].each_with_index do |transition, i|
      puts "  #{i + 1}. #{transition[:from_state]} → #{transition[:to_state]} (#{transition[:event]})"
    end
  end

  puts "\n✨ Demo complete!"
end
