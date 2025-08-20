# frozen_string_literal: true

class ApplicationStarGatesController < ApplicationController
  # GET /application_star_gates - List ApplicationStarGate features
  def index
    application_features = find_application_star_gate_features

    render json: {
      application_features: application_features.map do |feature|
        {
          name: feature.feature_identifier,
          class_name: feature.class.name,
          status: feature.status,
          configuration: feature.configuration_summary,
          performance: feature.performance_stats,
          telemetry_tags: feature.class.telemetry_tags
        }
      end,
      total_count: application_features.size
    }
  end

  # GET /application_star_gates/:id/introspection - Deep introspection
  def introspection
    feature = find_application_feature(params[:id])
    return render_not_found unless feature

    render json: {
      introspection: feature.to_h,
      configuration_summary: feature.configuration_summary,
      performance_stats: feature.performance_stats,
      feature_identifier: feature.feature_identifier,
      telemetry_tags: feature.class.telemetry_tags,
      config_access: {
        timeout: feature.timeout,
        retry_count: feature.retry_count,
        circuit_breaker_threshold: feature.circuit_breaker_threshold,
        cache_ttl: feature.cache_ttl
      },
      state_specific_configs: {
        current_state: feature.status,
        feature_config: feature.feature_config,
        default_config: feature.default_config
      }
    }
  end

  # POST /application_star_gates/:id/execute - Execute with instrumentation
  def execute
    feature = find_application_feature(params[:id])
    return render_not_found unless feature

    context = params[:context] || {}
    start_time = Time.current

    begin
      result = feature.execute(context) do
        # Simulate some work
        sleep(0.01) if params[:simulate_work]
        params[:test_payload] || 'ApplicationStarGate execution successful'
      end

      render json: {
        feature_id: params[:id],
        result: result,
        context: context,
        execution_time_ms: ((Time.current - start_time) * 1000).round(2),
        performance_stats: feature.performance_stats,
        executed_at: Time.current
      }
    rescue StandardError => e
      render json: {
        error: e.message,
        execution_time_ms: ((Time.current - start_time) * 1000).round(2)
      }, status: :internal_server_error
    end
  end

  # POST /application_star_gates/:id/transition - Change feature state
  def transition
    feature = find_application_feature(params[:id])
    return render_not_found unless feature

    event = params[:event]
    return render json: { error: 'Event parameter required' }, status: :bad_request unless event

    begin
      case event
      when 'enable'
        feature.enable
      when 'disable'
        feature.disable
      when 'rollout_canary'
        feature.rollout_canary
      else
        return render json: { error: "Unknown event: #{event}" }, status: :bad_request
      end

      render json: {
        feature_id: params[:id],
        event: event,
        new_status: feature.status,
        transition_count: feature.transition_count,
        transitioned_at: Time.current
      }
    rescue StandardError => e
      render json: { error: e.message }, status: :unprocessable_entity
    end
  end

  private

  def find_application_star_gate_features
    # In a real app, you'd have a registry of your ApplicationStarGate instances
    # For demo purposes, we'll create some examples
    [
      DemoPaymentFeature.new(rollout: 25),
      DemoNotificationFeature.new(rollout: 50),
      DemoExperimentalFeature.new(rollout: 10)
    ]
  end

  def find_application_feature(identifier)
    find_application_star_gate_features.find do |feature|
      feature.feature_identifier == identifier ||
        feature.class.name.underscore.gsub('_', '-') == identifier
    end
  end

  def render_not_found
    render json: { error: 'ApplicationStarGate feature not found' }, status: :not_found
  end
end
