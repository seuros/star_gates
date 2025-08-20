# frozen_string_literal: true

class Demo::PaymentsController < ApplicationController
  before_action :setup_payment_feature

  def process_payment
    amount = params[:amount]&.to_f || 100.0
    currency = params[:currency] || 'USD'

    result = @payment_feature.process_payment(amount, currency)

    render json: {
      payment_result: result,
      feature_status: @payment_feature.status,
      performance_stats: @payment_feature.performance_stats
    }
  end

  def methods
    methods = @payment_feature.get_payment_methods

    render json: {
      available_methods: methods,
      feature_status: @payment_feature.status,
      processor: @payment_feature.feature_config['processor']
    }
  end

  def calculate_fees
    amount = params[:amount]&.to_f || 100.0
    fees = @payment_feature.calculate_fees(amount)

    render json: {
      amount: amount,
      fees: fees,
      fee_structure: @payment_feature.feature_config['fee_structure'],
      feature_status: @payment_feature.status
    }
  end

  private

  def setup_payment_feature
    @payment_feature = DemoPaymentFeature.new(rollout: 50, group: :beta_users)

    # Set state based on params for testing
    case params[:state]
    when 'enabled'
      @payment_feature.enable
    when 'canary'
      @payment_feature.rollout_canary
    when 'disabled'
      @payment_feature.disable
    end
  end
end
