# BreakerMachines API Specs for StarGates Integration

## Current StarGates Circuit Expectations

StarGates expects the following methods on circuit breaker instances:

### Core Execution
- `call(&block)` - Execute block with circuit breaker protection ✅ **Available**
- `open?` - Check if circuit is open ✅ **Available**
- `closed?` - Check if circuit is closed ✅ **Available**
- `half_open?` - Check if circuit is half-open ✅ **Available**

### Statistics & Introspection
- `last_failure_time` - Timestamp of last failure ❌ **Missing**
- `failure_count` - Number of recent failures ❌ **Missing Direct Access**
- `success_count` - Number of recent successes ❌ **Missing Direct Access**

### Control
- `reset!` - Reset circuit to closed state ✅ **Available** (as `reset`)

## Required BreakerMachines Enhancements

### 1. Direct Statistics Access Methods

Add these convenience methods to `BreakerMachines::Circuit::Introspection`:

```ruby
module BreakerMachines
  class Circuit
    module Introspection
      # Direct access to last failure timestamp
      def last_failure_time
        @last_failure_at.value
      end

      # Alias for consistency with StarGates expectations
      alias last_failure_at last_failure_time

      # Direct access to failure count in current window
      def failure_count
        @storage.failure_count(@name, @config[:failure_window])
      end

      # Direct access to success count in current window
      def success_count
        @storage.success_count(@name, @config[:failure_window])
      end
    end
  end
end
```

### 2. State Management Method Alias

Add reset! alias to `BreakerMachines::Circuit::StateManagement`:

```ruby
module BreakerMachines
  class Circuit
    module StateManagement
      # Alias for StarGates compatibility
      def reset!
        reset
      end
    end
  end
end
```

## StarGates Circuit Mapping

With these additions, StarGates Circuit will map cleanly:

```ruby
module StarGates
  class Circuit
    def create_breaker
      circuit_name = "star_gates_circuit_#{object_id}"

      BreakerMachines::Circuit.new(circuit_name, {
        failure_threshold: threshold,
        failure_window: within,
        reset_timeout: reset_after,
        exceptions: [StandardError]
      })
    end

    # Direct delegation - no more stats() calls needed
    delegate :last_failure_time, :failure_count, :success_count, :reset!, to: :breaker
    delegate :call, :open?, :closed?, :half_open?, to: :breaker
  end
end
```

## Benefits

1. **Performance**: Direct method access instead of calling `stats()` hash every time
2. **API Consistency**: StarGates gets the exact method names it expects
3. **Backward Compatibility**: All existing BreakerMachines functionality remains unchanged
4. **Clean Integration**: StarGates Circuit becomes a thin wrapper with no complex mapping

## Implementation Priority

1. **High Priority**: `last_failure_time`, `failure_count`, `success_count` methods
2. **Medium Priority**: `reset!` alias for consistency
3. **Low Priority**: Additional convenience methods if needed

## Test Requirements

The enhancements should pass these StarGates test scenarios:

```ruby
circuit = BreakerMachines::Circuit.new('test_circuit', failure_threshold: 1)

# Should work after failures
begin
  circuit.call { raise StandardError }
rescue StandardError
  # These should all work without calling stats()
  circuit.last_failure_time.should be_a(Numeric)
  circuit.failure_count.should == 1
  circuit.success_count.should == 0
end

# Should work after success
circuit.call { "success" }
circuit.success_count.should == 1

# Reset should work with both methods
circuit.reset!  # StarGates expectation
circuit.reset   # BreakerMachines original
```

## Alternative: Configuration Option

If you prefer not to add these methods globally, we could add a compatibility mode:

```ruby
BreakerMachines::Circuit.new('test', {
  failure_threshold: 5,
  star_gates_compatibility: true  # Enables the additional methods
})
```

But I recommend adding them globally since they're useful introspection methods that any user might want.
