# JSON-RPC Migration Guide

StarGates now supports the `jsonrpc-rails` gem for better Rails integration. The legacy JSON-RPC implementation is deprecated and will be removed in a future version.

## Installation

Add `jsonrpc-rails` to your Gemfile:

```ruby
gem 'star_gates'
gem 'jsonrpc-rails'
```

## Migration from Legacy JSON-RPC

### Before (Legacy - Deprecated)

```ruby
# Old way - will show deprecation warnings
handler = StarGates.jsonrpc_handler
rack_app = StarGates.jsonrpc_rack_app

# Manual request handling
response = handler.handle_request(request_body)
render json: JSON.parse(response)
```

### After (New jsonrpc-rails Integration)

```ruby
# app/controllers/api/v1/features_controller.rb
class Api::V1::FeaturesController < ApplicationController
  include StarGates::JsonrpcRailsAdapter

  # POST /api/v1/features/rpc
  # Automatically handles JSON-RPC 2.0 requests and batch requests
end
```

## Configuration

```ruby
# config/application.rb
config.jsonrpc_rails.validated_paths = [
  "/api/v1/features/rpc",
  %r{\A/api/v\d+/features/rpc\z}
]

# config/routes.rb
Rails.application.routes.draw do
  namespace :api do
    namespace :v1 do
      post 'features/rpc', to: 'features#process'
    end
  end
end
```

## Available JSON-RPC Methods

All the same methods are available:

### Feature Management
- `feature.create` - Create new features
- `feature.get` - Get feature details
- `feature.list` - List features (optionally filtered by state)
- `feature.changeState` - Change feature state
- `feature.execute` - Record feature execution
- `feature.evaluate` - Record feature evaluation

### System Operations
- `system.health` - Health check
- `system.rebuildProjections` - Rebuild read model projections
- `feature.stats` - Get feature statistics
- `feature.recentTransitions` - Get recent state transitions

## Benefits of jsonrpc-rails Integration

1. **Native Rails Integration**: Better middleware, logging, and error handling
2. **Batch Support**: Automatic handling of JSON-RPC batch requests
3. **Cleaner Code**: ~200 lines of boilerplate removed from StarGates
4. **Better Testing**: Use Rails test helpers instead of custom mocks
5. **Standards Compliance**: Proven JSON-RPC 2.0 implementation

## Example Usage

### Single Request
```bash
curl -X POST /api/v1/features/rpc \
  -H "Content-Type: application/json" \
  -d '{
    "jsonrpc": "2.0",
    "method": "feature.create",
    "params": {
      "featureId": "new_checkout",
      "rollout": 25,
      "group": "beta_users"
    },
    "id": 1
  }'
```

### Batch Request
```bash
curl -X POST /api/v1/features/rpc \
  -H "Content-Type: application/json" \
  -d '[
    {
      "jsonrpc": "2.0",
      "method": "feature.list",
      "params": {"state": "canary"},
      "id": 1
    },
    {
      "jsonrpc": "2.0",
      "method": "system.health",
      "params": {},
      "id": 2
    }
  ]'
```

## Authentication & Authorization

```ruby
class Api::V1::FeaturesController < ApplicationController
  include StarGates::JsonrpcRailsAdapter

  before_action :authenticate_user!
  before_action :authorize_feature_management!

  private

  def authenticate_user!
    head :unauthorized unless current_user
  end

  def authorize_feature_management!
    head :forbidden unless current_user.can_manage_features?
  end
end
```

## Backward Compatibility

The legacy JSON-RPC implementation is still available but deprecated:

```ruby
# These will show deprecation warnings
StarGates.jsonrpc_handler
StarGates.jsonrpc_rack_app
```

## Migration Timeline

- **Current**: Legacy JSON-RPC deprecated, jsonrpc-rails integration available
- **Next Major Version**: Legacy JSON-RPC implementation will be removed
- **Recommendation**: Migrate to jsonrpc-rails immediately

## Testing

```ruby
# test/controllers/api/v1/features_controller_test.rb
class Api::V1::FeaturesControllerTest < ActionDispatch::IntegrationTest
  test "creates feature via JSON-RPC" do
    post '/api/v1/features/rpc',
         params: {
           jsonrpc: '2.0',
           method: 'feature.create',
           params: { featureId: 'test_feature', rollout: 50 },
           id: 1
         }.to_json,
         headers: { 'Content-Type' => 'application/json' }

    assert_response :success
    response_data = JSON.parse(response.body)
    assert_equal '2.0', response_data['jsonrpc']
    assert_equal 1, response_data['id']
    assert response_data['result']['featureId']
  end
end
```

## Need Help?

- Check the [jsonrpc-rails documentation](https://github.com/seuros/jsonrpc-rails)
- See examples in `examples/jsonrpc_rails_setup.rb`
- Review tests in `test/jsonrpc_rails_adapter_test.rb`
