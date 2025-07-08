# frozen_string_literal: true

class FeaturesController < ApplicationController
  # GET /features - List all registered features
  def index
    render json: {
      features: StarGates.feature_overview,
      statistics: StarGates.rollout_statistics,
      state_distribution: StarGates.state_distribution
    }
  end

  # GET /features/:name - Get specific feature details
  def show
    feature_name = params[:name]
    return render json: { error: 'Feature name is required' }, status: :bad_request unless feature_name

    feature_symbol = feature_name.to_sym

    begin
      gate = StarGates[feature_symbol]
      feature = gate.feature

      render json: {
        feature: feature.to_h,
        gate_status: gate.status,
        introspection: feature_introspection(feature)
      }
    rescue StarGates::GateNotFoundError
      render json: { error: "Feature '#{feature_name}' not found" }, status: :not_found
    end
  end

  # POST /features/:name/activate - Activate a feature for testing
  def activate
    feature_name = params[:name]
    return render json: { error: 'Feature name is required' }, status: :bad_request unless feature_name

    feature_symbol = feature_name.to_sym
    context = params[:context] || {}

    begin
      result = StarGates.activate(feature_symbol, context)
      render json: {
        feature: feature_name,
        result: result,
        context: context,
        activated_at: Time.current
      }
    rescue StarGates::GateNotFoundError
      render json: { error: "Feature '#{feature_name}' not found" }, status: :not_found
    rescue StandardError => e
      render json: { error: e.message }, status: :internal_server_error
    end
  end

  # GET /features/recent_transitions - Get recent state transitions
  def recent_transitions
    limit = params[:limit]&.to_i || 10

    render json: StarGates.recent_transitions(limit: limit)
  end

  private

  def feature_introspection(feature)
    return {} unless feature.respond_to?(:stats)

    {
      stats: feature.stats,
      configuration: feature.configuration,
      summary: feature.summary,
      transition_history: feature.transition_history(limit: 5)
    }
  end
end
