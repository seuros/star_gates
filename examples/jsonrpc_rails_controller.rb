# frozen_string_literal: true

# Example controller showing how to use StarGates with jsonrpc-rails
class StarGatesApiController < ApplicationController
  include StarGates::JsonrpcRailsAdapter

  # This automatically handles JSON-RPC requests
  # POST /star_gates_api/process
  #
  # Example request:
  # {
  #   "jsonrpc": "2.0",
  #   "method": "feature.create",
  #   "params": {
  #     "featureId": "payment_v2",
  #     "rollout": 25,
  #     "group": "beta_users"
  #   },
  #   "id": 1
  # }
  #
  # Example batch request:
  # [
  #   {
  #     "jsonrpc": "2.0",
  #     "method": "feature.create",
  #     "params": { "featureId": "feature_1", "rollout": 50 },
  #     "id": 1
  #   },
  #   {
  #     "jsonrpc": "2.0",
  #     "method": "feature.get",
  #     "params": { "featureId": "feature_1" },
  #     "id": 2
  #   }
  # ]

  protected

  # Optional: Override to customize feature service
  def feature_service
    @feature_service ||= begin
      # Enable event sourcing for JSON-RPC API
      StarGates.enable_event_sourcing! unless StarGates.feature_service_enabled?
      StarGates.feature_service
    end
  end
end
