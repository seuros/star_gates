# StarGates Examples

This directory contains practical examples demonstrating StarGates features and capabilities.

## Available Examples

### 🚀 [transition_demo.rb](transition_demo.rb)
Demonstrates the comprehensive transition history tracking system:
- Individual feature state transitions
- System-wide transition aggregation
- LLM-friendly introspection data
- Real-time transition monitoring

```bash
ruby examples/transition_demo.rb
```

### 🔍 [introspection_demo.rb](introspection_demo.rb)
Showcases the complete introspection capabilities:
- Feature-level statistics and summaries
- System-wide overview and analytics
- User simulation and debugging
- Rollout scenario analysis

```bash
ruby examples/introspection_demo.rb
```

### 💳 [payment_feature.rb](payment_feature.rb)
Real-world example of a payment feature with state-specific behavior:
- Custom feature implementation
- State-dependent configuration
- Payment service integration
- Transition history tracking

```bash
ruby examples/payment_feature.rb
```

## Key Features Demonstrated

### State Machine Integration
- **Disabled** → **Canary** → **Enabled** state transitions
- State-specific method implementations
- Automatic transition history recording

### Introspection Capabilities
- Complete feature lifecycle tracking
- User eligibility debugging
- System-wide analytics
- LLM-friendly structured data

### Thread-Safe Operations
- Concurrent transition recording
- Thread-safe state management
- Memory-efficient history storage

### Real-World Usage Patterns
- Feature flags in service classes
- Configuration management per state
- Progressive rollout strategies
- Debugging and monitoring

## Running Examples

All examples can be run directly from the project root:

```bash
# From the star_gates project root
ruby examples/transition_demo.rb
ruby examples/introspection_demo.rb
ruby examples/payment_feature.rb
```

The examples demonstrate how StarGates provides comprehensive visibility and control over feature flags, making it the "Superior" feature flag system for modern applications.
