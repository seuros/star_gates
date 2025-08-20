# StarGates Rails Integration Demo

## Overview

StarGates has been successfully integrated into a Rails application with comprehensive API endpoints demonstrating both basic feature flags and enhanced ApplicationStarGate functionality with ActiveSupport integration.

## Setup Complete

✅ **Rails App Structure**: Test/dummy Rails application set up
✅ **Gem Integration**: StarGates gem loaded and working in Rails
✅ **ActiveSupport Integration**: Full ActiveSupport features enabled
✅ **API Endpoints**: RESTful API for feature flag management
✅ **Demo Controllers**: Real-world examples of feature usage
✅ **Event Notifications**: ActiveSupport::Notifications integration

## Running the Demo

### Start the Rails Server

```bash
cd test/dummy
bundle install
bundle exec rails server -p 3001
```

### Available API Endpoints

#### Basic Feature Flags API

```bash
# List all feature flags
curl -s http://localhost:3001/features | jq '.features.summary'

# Get specific feature details
curl -s http://localhost:3001/features/legacy_payment | jq '.feature'

# Activate a feature for testing
curl -s -X POST http://localhost:3001/features/new_dashboard/activate | jq '.result'

# Get recent state transitions
curl -s http://localhost:3001/features/recent_transitions | jq '.transitions'
```

#### ApplicationStarGate Enhanced API

```bash
# List ApplicationStarGate features
curl -s http://localhost:3001/application_star_gates | jq '.application_features[]'

# Deep introspection
curl -s http://localhost:3001/application_star_gates/demo_payment_processing/introspection | jq '.configuration_summary'

# Execute with instrumentation
curl -s -X POST http://localhost:3001/application_star_gates/demo_payment_processing/execute | jq '.execution_time_ms'

# State transitions
curl -s -X POST http://localhost:3001/application_star_gates/demo_notification_system/transition -d "event=enable" | jq '.new_status'
```

#### Demo Business Logic APIs

```bash
# Payment Processing Demo
curl -s -X POST 'http://localhost:3001/demo/payment?state=enabled&amount=250' | jq '.payment_result'

# Get available payment methods
curl -s 'http://localhost:3001/demo/payment/methods?state=canary' | jq '.available_methods'

# Calculate fees
curl -s 'http://localhost:3001/demo/payment/fees?amount=100&state=enabled' | jq '.fees'

# Notification System Demo
curl -s -X POST 'http://localhost:3001/demo/notification?state=enabled' -d 'message=Test notification' | jq '.notification_result'

# AI Recommendations Demo
curl -s -X POST 'http://localhost:3001/demo/ai/recommendations?state=enabled' | jq '.recommendations'
```

## Key Features Demonstrated

### 1. **Basic Feature Flags**
- Simple rollout percentages and group targeting
- State machine transitions (disabled → canary → enabled)
- System-wide statistics and introspection

### 2. **ApplicationStarGate Enhanced Features**
- **ActiveSupport::Configurable**: Flexible configuration management
- **ActiveSupport::HashWithIndifferentAccess**: String/symbol key flexibility
- **ActiveSupport::Notifications**: Event monitoring and instrumentation
- **State-specific configurations**: Different configs per feature state
- **Performance monitoring**: Execution time and error rate tracking
- **Team-based telemetry**: Organizational metrics tagging

### 3. **Real-world Business Logic Examples**

#### Payment Processing Feature
- **Enabled State**: Stripe Connect with v3 API, fraud detection, webhooks
- **Canary State**: Stripe Standard with v2 API, basic validation
- **Disabled State**: Legacy gateway with v1 API

#### Notification System Feature
- **Enabled State**: Multi-channel (email, SMS, push, in-app), real-time delivery
- **Canary State**: Limited channels (email, push), batched delivery
- **Disabled State**: Email only, legacy delivery

#### AI Recommendations Feature
- **Enabled State**: GPT-4, 10 recommendations, real-time learning
- **Canary State**: GPT-3.5, 5 recommendations, no learning
- **Disabled State**: Rule-based, 3 recommendations

## ActiveSupport Integration Benefits

### 1. **Event Monitoring**
```ruby
# Subscribe to all StarGates events
ActiveSupport::Notifications.subscribe(/star_gates\./) do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  Rails.logger.info "Event: #{name}, Duration: #{duration}ms"
end
```

### 2. **Flexible Configuration**
```ruby
class PaymentFeature < StarGates::ApplicationStarGate
  configure 'payment_processing',
           timeout: 5.0,
           performance_monitoring: true,
           enabled_config: { api_version: 'v3', processor: 'stripe_connect' }

  for_team 'payments'
end
```

### 3. **String/Symbol Key Flexibility**
```ruby
config = feature.feature_config
config[:api_version]   # Works
config['api_version']  # Also works (HashWithIndifferentAccess)
```

## Testing the Integration

### Rails Console Testing
```bash
cd test/dummy
bundle exec rails console

# Test basic functionality
payment_feature = DemoPaymentFeature.new(rollout: 50)
payment_feature.rollout_canary
puts payment_feature.feature_config
result = payment_feature.process_payment(100.0, 'USD')
puts payment_feature.performance_stats
```

### API Testing Results

**Feature Flags Overview**:
```json
{
  "by_status": { "disabled": 4 },
  "total_features": 4,
  "features_with_circuits": 0
}
```

**Payment Processing (Enabled State)**:
```json
{
  "success": true,
  "transaction_id": "demo_1752300704_718",
  "processor": "stripe_connect",
  "api_version": "v3",
  "features_used": ["fraud_detection", "webhooks", "real_time_validation"],
  "fee_structure": "connect_pricing"
}
```

**ApplicationStarGate Configuration**:
```json
{
  "timeout": 3.0,
  "retry_count": 3,
  "circuit_breaker_threshold": 5,
  "performance_monitoring": true
}
```

## Architecture Highlights

### 1. **Rails Engine Pattern**
- StarGates integrates as a standard Rails gem
- No special configuration required
- Works with existing Rails middleware stack

### 2. **ActiveSupport Deep Integration**
- Uses Rails' notification system for monitoring
- Leverages ActiveSupport's configuration patterns
- Benefits from Rails' hash and core extensions

### 3. **RESTful API Design**
- Standard Rails controller patterns
- JSON responses with proper HTTP status codes
- Resource-based routing

### 4. **Production-Ready Features**
- Error handling and validation
- Performance monitoring
- State transition tracking
- Comprehensive introspection

## Next Steps

This demo proves StarGates can be:
1. **Easily integrated** into existing Rails applications
2. **Enhanced with ActiveSupport** for better DX
3. **Monitored and debugged** using Rails patterns
4. **Extended with business logic** for real-world use cases
5. **Tested and validated** using Rails testing frameworks

The Rails integration is **production-ready** and demonstrates the full power of StarGates with modern Rails applications.

## Performance & Monitoring

- ✅ ActiveSupport::Notifications integration for real-time monitoring
- ✅ Built-in performance tracking (execution time, error rates)
- ✅ Rails logger integration for debugging
- ✅ Team-based telemetry tagging for organizational metrics
- ✅ State transition history for auditing
- ✅ Comprehensive introspection for troubleshooting

**StarGates + Rails = Production-Ready Feature Flag Management! 🚀**
