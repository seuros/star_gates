# frozen_string_literal: true

# Example setup for using StarGates with jsonrpc-rails
#
# Add to your Gemfile:
# gem 'star_gates'
# gem 'jsonrpc-rails'
#
# In config/application.rb:

require 'star_gates'

module MyApp
  class Application < Rails::Application
    # Configure JSON-RPC validation paths
    config.jsonrpc_rails.validated_paths = [
      "/api/v1/star_gates/rpc",    # exact string
      %r{\A/api/v\d+/features\z},  # regexp
      ->(path) { path.start_with?("/admin/features") } # lambda
    ]
  end
end

# In config/routes.rb:
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post 'star_gates/rpc', to: 'star_gates_api#process'
    end
  end
end

# Create app/controllers/api/v1/star_gates_api_controller.rb:
class Api::V1::StarGatesApiController < ApplicationController
  include StarGates::JsonrpcRailsAdapter

  # Optional: Add authentication
  before_action :authenticate_user!

  # Optional: Add authorization
  before_action :authorize_feature_management!

  protected

  def feature_service
    @feature_service ||= begin
      StarGates.enable_event_sourcing!
      StarGates.feature_service
    end
  end

  private

  def authenticate_user!
    # Your authentication logic
    head :unauthorized unless current_user
  end

  def authorize_feature_management!
    # Your authorization logic
    head :forbidden unless current_user.can_manage_features?
  end
end

# Usage examples:

# Create a feature
curl -X POST http://localhost:3000/api/v1/star_gates/rpc \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "feature.create",
    "params": {
      "featureId": "new_checkout",
      "rollout": 25,
      "group": "beta_users",
      "metadata": {
        "team": "payments",
        "description": "New checkout flow"
      }
    },
    "id": 1
  }'

# Change feature state
curl -X POST http://localhost:3000/api/v1/star_gates/rpc \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "feature.changeState",
    "params": {
      "featureId": "new_checkout",
      "fromState": "disabled",
      "toState": "canary",
      "event": "rollout_canary",
      "context": {
        "reason": "Ready for beta testing",
        "requestedBy": "john@company.com"
      }
    },
    "id": 2
  }'

# Batch request
curl -X POST http://localhost:3000/api/v1/star_gates/rpc \
  -H "Content-Type: application/json" \
  -d '[
    {
      "jsonrpc": "2.0",
      "method": "feature.list",
      "params": { "state": "canary" },
      "id": 1
    },
    {
      "jsonrpc": "2.0",
      "method": "system.health",
      "params": {},
      "id": 2
    }
  ]'
