# frozen_string_literal: true

class DemoPaymentFeature < StarGates::ApplicationStarGate
  configure 'demo_payment_processing',
            timeout: 3.0,
            retry_count: 3,
            circuit_breaker_threshold: 5,
            performance_monitoring: true,
            instrumentation: true,
            enabled_config: {
              api_version: 'v3',
              processor: 'stripe_connect',
              features: %w[fraud_detection webhooks real_time_validation],
              fee_structure: 'connect_pricing'
            },
            canary_config: {
              api_version: 'v2',
              processor: 'stripe_standard',
              features: %w[webhooks basic_validation],
              fee_structure: 'standard_pricing'
            },
            disabled_config: {
              api_version: 'v1',
              processor: 'legacy_gateway',
              features: [],
              fee_structure: 'legacy_pricing'
            }

  for_team 'payments'

  def process_payment(amount, currency = 'USD')
    config = feature_config
    processor = config['processor']

    execute do
      {
        success: true,
        transaction_id: "demo_#{Time.current.to_i}_#{rand(1000)}",
        amount: amount,
        currency: currency,
        processor: processor,
        api_version: config['api_version'],
        features_used: config['features'],
        fee_structure: config['fee_structure'],
        processed_at: Time.current
      }
    end
  end

  def get_payment_methods
    config = feature_config

    case config['processor']
    when 'stripe_connect'
      %w[credit_card debit_card bank_transfer apple_pay google_pay]
    when 'stripe_standard'
      %w[credit_card debit_card apple_pay]
    else
      %w[credit_card debit_card]
    end
  end

  def calculate_fees(amount)
    config = feature_config

    case config['fee_structure']
    when 'connect_pricing'
      (amount * 0.029).round(2) # 2.9%
    when 'standard_pricing'
      ((amount * 0.029) + 0.30).round(2) # 2.9% + $0.30
    else
      ((amount * 0.035) + 0.25).round(2) # 3.5% + $0.25
    end
  end
end
