# frozen_string_literal: true

require_relative '../lib/star_gates'

module StarGates
  module Examples
    # Example PaymentFeature using ApplicationStarGate with ActiveSupport features
    class ApplicationPaymentFeature < StarGates::ApplicationStarGate
      # Configure this feature class using ActiveSupport::Configurable
      configure 'advanced_payment_processing',
                timeout: 5.0,
                retry_count: 3,
                circuit_breaker_threshold: 10,
                performance_monitoring: true,
                instrumentation: true,
                # State-specific configurations using ActiveSupport::HashWithIndifferentAccess
                enabled_config: {
                  'api_version' => 'v3',
                  'processor' => 'stripe_connect',
                  'webhook_enabled' => true,
                  'fraud_detection' => true,
                  'features' => %w[advanced_routing real_time_fraud]
                },
                canary_config: {
                  'api_version' => 'v2',
                  'processor' => 'stripe_standard',
                  'webhook_enabled' => true,
                  'fraud_detection' => false,
                  'features' => ['basic_routing']
                },
                disabled_config: {
                  'api_version' => 'v1',
                  'processor' => 'legacy_gateway',
                  'webhook_enabled' => false,
                  'fraud_detection' => false,
                  'features' => []
                }

      # Team-specific tagging for telemetry using ActiveSupport
      for_team 'payments'

      def initialize(rollout: 0, group: nil)
        super
      end

      # Override state-specific methods for payment-specific behavior
      # This method benefits from ActiveSupport::HashWithIndifferentAccess - can use string or symbol keys
      def process_payment_with_config(amount, currency = 'USD')
        config = feature_config
        processor = config[:processor] || config['processor'] || 'legacy_gateway'
        api_version = config[:api_version] || config['api_version'] || 'v1'
        features = config[:features] || config['features'] || []

        puts "Processing $#{amount} #{currency} with #{processor} (API #{api_version})"
        puts "Available features: #{features.join(', ')}" if features.any?

        case processor
        when 'stripe_connect'
          process_stripe_connect_payment(amount, currency, config)
        when 'stripe_standard'
          process_stripe_standard_payment(amount, currency, config)
        else
          process_legacy_payment(amount, currency, config)
        end
      end

      private

      def process_stripe_connect_payment(amount, _currency, config)
        # ActiveSupport::HashWithIndifferentAccess allows flexible key access
        {
          success: true,
          transaction_id: "sc_#{Time.now.to_i}_#{rand(1000)}",
          processor: 'stripe_connect',
          api_version: config['api_version'],
          fraud_checked: config['fraud_detection'],
          webhook_sent: config['webhook_enabled'],
          available_features: config['features'],
          fees: calculate_connect_fees(amount)
        }
      end

      def process_stripe_standard_payment(amount, _currency, config)
        # Mixed symbol and string access thanks to HashWithIndifferentAccess
        {
          success: true,
          transaction_id: "ss_#{Time.now.to_i}_#{rand(1000)}",
          processor: 'stripe_standard',
          api_version: config[:api_version],
          fraud_checked: config['fraud_detection'],
          webhook_sent: config[:webhook_enabled],
          available_features: config[:features],
          fees: calculate_standard_fees(amount)
        }
      end

      def process_legacy_payment(amount, _currency, config)
        {
          success: true,
          transaction_id: "legacy_#{Time.now.to_i}_#{rand(1000)}",
          processor: 'legacy_gateway',
          api_version: config['api_version'],
          fraud_checked: false,
          webhook_sent: false,
          available_features: [],
          fees: calculate_legacy_fees(amount)
        }
      end

      def calculate_connect_fees(amount)
        (amount * 0.029).round(2) # 2.9% for Stripe Connect
      end

      def calculate_standard_fees(amount)
        ((amount * 0.029) + 0.30).round(2) # 2.9% + $0.30 for standard
      end

      def calculate_legacy_fees(amount)
        ((amount * 0.035) + 0.25).round(2) # 3.5% + $0.25 for legacy
      end
    end

    # Enhanced payment service using ApplicationStarGate features
    class EnhancedPaymentService
      def initialize(user:, amount:, currency: 'USD')
        @user = user
        @amount = amount
        @currency = currency
        @payment_feature = ApplicationPaymentFeature.new(rollout: 30, group: :premium_users)
      end

      def process_payment
        context = { user: @user, amount: @amount, currency: @currency }

        # Use the enhanced execute method with instrumentation
        result = @payment_feature.execute(context) do
          @payment_feature.process_payment_with_config(@amount, @currency)
        end

        # Show performance stats
        puts "Performance: #{@payment_feature.performance_stats}" if @payment_feature.performance_monitoring_enabled?

        result || fallback_payment
      end

      def payment_status_with_config
        {
          status: @payment_feature.status,
          config: @payment_feature.feature_config,
          timeout: @payment_feature.timeout,
          circuit_breaker: @payment_feature.circuit_breaker_threshold,
          performance: @payment_feature.performance_stats,
          introspection: @payment_feature.to_h
        }
      end

      private

      def fallback_payment
        puts 'Using fallback payment processing'
        {
          success: true,
          transaction_id: "fallback_#{Time.now.to_i}_#{rand(1000)}",
          processor: 'fallback',
          api_version: 'v1'
        }
      end
    end
  end
end

# Demo script when file is run directly
if __FILE__ == $PROGRAM_NAME
  require 'ostruct'

  puts '🚀 ApplicationStarGate Payment Feature Demo with ActiveSupport'
  puts '=' * 60

  # Subscribe to ActiveSupport::Notifications for monitoring
  ActiveSupport::Notifications.subscribe(/star_gates\./) do |name, start, finish, _id, payload|
    duration = (finish - start) * 1000
    puts "📊 Notification: #{name}"
    puts "   Duration: #{duration.round(2)}ms"
    puts "   Payload: #{payload.inspect}"
    puts '   ---'
  end

  # Create test users
  premium_user = OpenStruct.new(id: 123, groups: [:premium_users])
  regular_user = OpenStruct.new(id: 456, groups: [:regular])

  # Create enhanced payment services
  premium_payment = StarGates::Examples::EnhancedPaymentService.new(
    user: premium_user,
    amount: 250.00,
    currency: 'USD'
  )

  regular_payment = StarGates::Examples::EnhancedPaymentService.new(
    user: regular_user,
    amount: 100.00,
    currency: 'USD'
  )

  puts "\n📊 Testing ApplicationStarGate states with configuration...\n"

  # Test disabled state
  puts '=== DISABLED State ==='
  puts "Premium user config: #{premium_payment.payment_status_with_config[:config]}"
  result = premium_payment.process_payment
  puts "Payment result: #{result}\n"

  # Move to canary state
  premium_payment.instance_variable_get(:@payment_feature).rollout_canary
  regular_payment.instance_variable_get(:@payment_feature).rollout_canary

  puts '=== CANARY State ==='
  puts "Premium user config: #{premium_payment.payment_status_with_config[:config]}"
  puts "Regular user config: #{regular_payment.payment_status_with_config[:config]}"

  premium_result = premium_payment.process_payment
  regular_result = regular_payment.process_payment

  puts "Premium payment: #{premium_result}"
  puts "Regular payment: #{regular_result}\n"

  # Move to enabled state
  premium_payment.instance_variable_get(:@payment_feature).enable

  puts '=== ENABLED State ==='
  puts "Premium user config: #{premium_payment.payment_status_with_config[:config]}"
  enabled_result = premium_payment.process_payment
  puts "Enabled payment: #{enabled_result}\n"

  # Show enhanced introspection
  feature = premium_payment.instance_variable_get(:@payment_feature)
  puts '🔍 Enhanced ApplicationStarGate Introspection:'
  puts "Configuration summary: #{feature.configuration_summary}"
  puts "Performance stats: #{feature.performance_stats}"
  puts "Feature name: #{feature.feature_identifier}"
  puts "Environment: #{StarGates.configuration.environment}"

  # Show complete introspection data
  puts "\n📋 Complete Feature Data:"
  introspection = feature.to_h
  puts "Name: #{introspection[:name]}"
  puts "Environment: #{introspection[:environment]}"
  puts "Configuration: #{introspection[:configuration]}"
  puts "Performance: #{introspection[:performance]}"

  if feature.transition_count.positive?
    puts "\n📈 Transition History:"
    feature.transition_history(limit: 5)[:transitions].each_with_index do |transition, i|
      puts "  #{i + 1}. #{transition[:from_state]} → #{transition[:to_state]} (#{transition[:event]}) - #{transition[:duration_since].round(2)}s ago"
    end
  end

  puts "\n✨ ApplicationStarGate with ActiveSupport demo complete!"
  puts 'Key ActiveSupport features demonstrated:'
  puts '  • ActiveSupport::Configurable for flexible configuration'
  puts '  • ActiveSupport::HashWithIndifferentAccess for flexible key access'
  puts '  • ActiveSupport::Notifications for event monitoring'
  puts '  • ActiveSupport::Concern for modular functionality'
  puts '  • Deep merge and other core extensions'
  puts '  • Enhanced instrumentation and telemetry'
end
