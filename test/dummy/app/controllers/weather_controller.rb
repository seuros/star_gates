# frozen_string_literal: true

class WeatherController < ApplicationController
  include BreakerMachines::DSL

  NS_PER_SECOND = 1_000_000_000
  # Opens after 3 failures in a minute; probes again after 30 seconds.
  WEATHER_POLICY = BreakerMachines::Policy.new(BreakerMachines::Threshold.new(3, nil, 0), 60 * NS_PER_SECOND,
                                               BreakerMachines::Recovery.new(30 * NS_PER_SECOND, 0.0, 1, 1), nil)

  def circuit(name)
    case name
    when :weather_api
      dynamic_circuit(:weather_api, global: true) do
        policy WEATHER_POLICY
        fallback do |_error|
          {
            temperature: 72,
            condition: 'unknown',
            source: 'fallback',
            error: 'Weather service unavailable',
            circuit_open: true
          }
        end
      end
    else
      super
    end
  end

  def show
    weather_data = circuit(:weather_api).wrap do
      fetch_weather_from_external_api
    end

    render json: weather_data
  end

  def force_failure
    # Endpoint to simulate failures for testing
    weather = circuit(:weather_api)
    weather.wrap do
      raise 'Simulated weather API failure'
    end
    render json: {
      error: 'Simulated weather API failure',
      circuit_state: weather.stats.state,
      failure_count: weather.stats.failure_count
    }, status: :service_unavailable
  end

  private

  def fetch_weather_from_external_api
    # Failures are explicit via /force_failure, not random test failures.
    {
      temperature: rand(60..80),
      condition: %w[sunny cloudy rainy].sample,
      source: 'live',
      timestamp: Time.current
    }
  end
end
