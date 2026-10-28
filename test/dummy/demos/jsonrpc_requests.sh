#!/usr/bin/env bash
set -euo pipefail

# Optional jsonrpc-rails setup: see jsonrpc_rails_setup.rb.
endpoint="${BASE_URL:-http://localhost:3000}/api/v1/star_gates/rpc"

# Create a feature.
curl --fail-with-body -X POST "$endpoint" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "feature.create",
    "params": {
      "featureId": "new_checkout",
      "rollout": 25,
      "group": "beta",
      "metadata": { "team": "payments", "description": "New checkout flow" }
    },
    "id": 1
  }'

# Change feature state.
curl --fail-with-body -X POST "$endpoint" \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "feature.changeState",
    "params": {
      "featureId": "new_checkout",
      "fromState": "disabled",
      "toState": "canary",
      "event": "rollout_canary",
      "context": { "reason": "Ready for beta testing", "requestedBy": "john@company.com" }
    },
    "id": 2
  }'

# Batch request.
curl --fail-with-body -X POST "$endpoint" \
  -H "Content-Type: application/json" \
  -d '[
    { "jsonrpc": "2.0", "method": "feature.list", "params": { "state": "canary" }, "id": 1 },
    { "jsonrpc": "2.0", "method": "system.health", "params": {}, "id": 2 }
  ]'
