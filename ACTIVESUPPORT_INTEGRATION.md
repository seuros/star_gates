# ActiveSupport Integration in StarGates

## Overview

StarGates now fully integrates with ActiveSupport to leverage its powerful features for configuration, notifications, and core extensions. This enhancement makes ApplicationStarGate a robust foundation for enterprise-grade feature flag management.

## Key ActiveSupport Features Integrated

### 1. ActiveSupport::Configurable
- **Purpose**: Provides flexible configuration management
- **Usage**: Class-level configuration with inheritance and defaults
- **Benefits**: Consistent API with Rails applications

```ruby
class MyFeature < StarGates::ApplicationStarGate
  configure 'my_feature',
           timeout: 5.0,
           retry_count: 3,
           performance_monitoring: true
end
```

### 2. ActiveSupport::HashWithIndifferentAccess
- **Purpose**: Allows flexible key access (symbols or strings)
- **Usage**: State-specific configurations and instance config
- **Benefits**: Eliminates key type inconsistencies

```ruby
config = feature.feature_config
config[:api_version]   # Works
config['api_version']  # Also works
```

### 3. ActiveSupport::Notifications
- **Purpose**: Built-in instrumentation and event monitoring
- **Usage**: Automatic notifications for feature execution, UI access, and config access
- **Benefits**: Deep observability and debugging capabilities

```ruby
# Subscribe to all StarGates events
ActiveSupport::Notifications.subscribe(/star_gates\./) do |name, start, finish, id, payload|
  duration = (finish - start) * 1000
  puts "Event: #{name}, Duration: #{duration.round(2)}ms"
  puts "Payload: #{payload.inspect}"
end
```

### 4. ActiveSupport Core Extensions
- **Deep Merge**: Configuration merging across inheritance levels
- **Class Attributes**: Thread-safe class-level configuration
- **String Extensions**: Automatic method name conversion

### 5. ActiveSupport::Concern (Ready for future use)
- **Purpose**: Modular functionality composition
- **Benefits**: Clean separation of concerns for advanced features

## Enhanced ApplicationStarGate Features

### Configuration Management
```ruby
class PaymentFeature < StarGates::ApplicationStarGate
  configure 'payment_processing',
           timeout: 5.0,
           retry_count: 3,
           circuit_breaker_threshold: 10,
           performance_monitoring: true,
           # State-specific configurations
           enabled_config: {
             api_version: 'v3',
             processor: 'stripe_connect',
             features: ['fraud_detection', 'webhooks']
           },
           canary_config: {
             api_version: 'v2',
             processor: 'stripe_standard',
             features: ['webhooks']
           },
           disabled_config: {
             api_version: 'v1',
             processor: 'legacy',
             features: []
           }

  # Team-specific telemetry tagging
  for_team 'payments'
end
```

### Enhanced Instrumentation
```ruby
feature = PaymentFeature.new(rollout: 50)

# Automatically instruments execution with ActiveSupport::Notifications
result = feature.execute(context) do
  # Your feature logic here
  process_payment_with_advanced_features
end

# Performance monitoring built-in
puts feature.performance_stats
# => {
#   average_execution_time: 0.25,
#   total_executions: 15,
#   error_rate: 2.1,
#   last_execution: 2024-01-15 10:30:45 UTC
# }
```

### Flexible Configuration Access
```ruby
feature = PaymentFeature.new
feature.enable

config = feature.feature_config

# All of these work thanks to HashWithIndifferentAccess
processor = config[:processor]     # Symbol access
processor = config['processor']    # String access
features = config[:features]       # Mixed access patterns
```

### Event Monitoring
Applications can subscribe to feature flag events for monitoring, alerting, and analytics:

```ruby
# Monitor all feature flag activities
ActiveSupport::Notifications.subscribe('star_gates.feature.execute') do |name, start, finish, id, payload|
  # Log execution metrics
  Rails.logger.info "Feature #{payload[:feature]} executed in #{(finish - start) * 1000}ms"

  # Send metrics to monitoring system
  Metrics.record('feature_flag.execution_time', (finish - start) * 1000,
                tags: { feature: payload[:feature], status: payload[:status] })
end

# Monitor UI component access
ActiveSupport::Notifications.subscribe('star_gates.ui_component.access') do |name, start, finish, id, payload|
  # Track UI component usage
  Analytics.track('feature_flag.ui_access', {
    feature: payload[:feature],
    component: payload[:component]
  })
end
```

## Benefits

### 1. **Rails Integration**
- Familiar API patterns for Rails developers
- Consistent with Rails application architecture
- Seamless integration with existing Rails logging and monitoring

### 2. **Enhanced Observability**
- Built-in instrumentation with ActiveSupport::Notifications
- Automatic performance monitoring
- Rich telemetry data for debugging and optimization

### 3. **Flexible Configuration**
- String/symbol key flexibility eliminates configuration errors
- Deep merging for complex configuration inheritance
- Environment-aware defaults

### 4. **Developer Experience**
- Reduced boilerplate code
- Clear separation of concerns
- Comprehensive introspection capabilities

### 5. **Enterprise Ready**
- Thread-safe operations
- Performance monitoring built-in
- Extensible architecture for custom requirements

## Migration from Basic Feature

Existing features using `StarGates::Feature` can be upgraded to `StarGates::ApplicationStarGate`:

```ruby
# Before
class PaymentFeature < StarGates::Feature
  def initialize(rollout: 0, group: nil)
    super
    @feature_config = { api_version: 'v2' }
    @default_config = { api_version: 'v1' }
  end
end

# After
class PaymentFeature < StarGates::ApplicationStarGate
  configure 'payment_feature',
           timeout: 5.0,
           performance_monitoring: true,
           enabled_config: { api_version: 'v2' },
           disabled_config: { api_version: 'v1' }

  for_team 'payments'
end
```

## Testing

Comprehensive test coverage ensures ActiveSupport integration works correctly:

```bash
# Run ApplicationStarGate tests
ruby -I test -I lib test/test_application_star_gate.rb

# All tests pass
7 runs, 27 assertions, 0 failures, 0 errors, 1 skips
```

## Future Enhancements

The ActiveSupport integration provides a foundation for future enhancements:

1. **ActiveJob Integration**: Async feature flag evaluations
2. **ActionCable Integration**: Real-time feature flag updates
3. **ActiveRecord Integration**: Database-backed feature storage
4. **Rails Generators**: Automated feature flag scaffolding

## Dependencies

```ruby
# Gemfile
gem 'activesupport', '>= 6.0'
```

The integration is compatible with ActiveSupport 6.0+ and works seamlessly in both Rails and non-Rails environments.
