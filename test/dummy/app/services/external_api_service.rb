# frozen_string_literal: true

class ExternalApiService
  include BreakerMachines::DSL

  NS_PER_SECOND = 1_000_000_000
  # Opens after 3 failures in a minute; probes again after 30 seconds.
  PAYMENT_POLICY = BreakerMachines::Policy.new(BreakerMachines::Threshold.new(3, nil, 0), 60 * NS_PER_SECOND,
                                               BreakerMachines::Recovery.new(30 * NS_PER_SECOND, 0.0, 1, 1), nil)
  # Opens at a 50% failure rate over at least 10 calls in two minutes.
  EMAIL_POLICY = BreakerMachines::Policy.new(BreakerMachines::Threshold.new(nil, 0.5, 10), 120 * NS_PER_SECOND,
                                             BreakerMachines::Recovery.new(60 * NS_PER_SECOND, 0.0, 1, 1), nil)

  def circuit(name)
    case name
    when :payment_gateway
      dynamic_circuit(:payment_gateway, global: true) do
        policy PAYMENT_POLICY
        timeout 10 * NS_PER_SECOND

        fallback do |_error|
          {
            status: 'queued',
            message: 'Payment will be processed when service recovers',
            reference: SecureRandom.uuid
          }
        end

        on_open do
          Rails.logger.error 'Payment gateway circuit opened!'
        end

        on_close do
          Rails.logger.info 'Payment gateway circuit closed - service recovered'
        end
      end
    when :email_service
      dynamic_circuit(:email_service, global: true) do
        policy EMAIL_POLICY

        fallback do |error|
          # Don't retry emails, just log
          Rails.logger.warn "Email not sent due to circuit open: #{error.message}"
          { sent: false, queued: true }
        end
      end
    else
      super
    end
  end

  def process_payment(amount, _card_token)
    circuit(:payment_gateway).wrap do
      # Simulate payment processing
      raise 'Payment gateway timeout' if rand > 0.9 # 10% failure rate

      {
        status: 'success',
        transaction_id: SecureRandom.uuid,
        amount: amount,
        timestamp: Time.current
      }
    end
  end

  def send_notification(_email, _subject, _body)
    circuit(:email_service).wrap do
      # Simulate email sending
      raise 'SMTP connection failed' if rand > 0.95 # 5% failure rate

      {
        sent: true,
        message_id: SecureRandom.uuid,
        timestamp: Time.current
      }
    end
  end

  # Example of checking circuit state before expensive operations
  def can_process_payments?
    !circuit(:payment_gateway).open?
  end

  def service_status
    payment_stats = circuit(:payment_gateway).stats
    email_stats = circuit(:email_service).stats

    {
      payment_gateway: {
        available: !circuit(:payment_gateway).open?,
        state: payment_stats.state,
        failure_count: payment_stats.failure_count
      },
      email_service: {
        available: !circuit(:email_service).open?,
        state: email_stats.state,
        failure_count: email_stats.failure_count
      }
    }
  end
end
