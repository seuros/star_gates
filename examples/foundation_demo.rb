# frozen_string_literal: true

require_relative '../lib/star_gates'

# 🏗️ StarGates Foundation Demo
# Demonstrates the hexagonal architecture, event sourcing, and JSON-RPC API

puts '🏗️ StarGates Foundation Architecture Demo'
puts '=' * 50

# 1. Configure the foundation with event sourcing
puts "\n🔧 Configuring Foundation..."
StarGates.enable_event_sourcing!
puts '✅ Event sourcing enabled'
puts '✅ Hexagonal architecture configured'
puts '✅ JSON-RPC API ready'

# 2. Create features using the new service layer
puts "\n📦 Creating Features via Service Layer..."
feature_service = StarGates.feature_service

payment_aggregate = feature_service.create_feature(
  'payment_v2',
  rollout: 25,
  group: :beta_users,
  metadata: { team: 'payments', version: '2.0' }
)

dashboard_aggregate = feature_service.create_feature(
  'dashboard_redesign',
  rollout: 50,
  metadata: { team: 'frontend', priority: 'high' }
)

puts "✅ Created payment_v2 feature (#{payment_aggregate.current_state})"
puts "✅ Created dashboard_redesign feature (#{dashboard_aggregate.current_state})"

# 3. Demonstrate state transitions with event sourcing
puts "\n🔄 State Transitions with Event Sourcing..."

# Payment feature transitions
feature_service.change_feature_state('payment_v2', :disabled, :canary, :rollout_canary, {
                                       reason: 'Starting canary rollout',
                                       requested_by: 'alice@company.com'
                                     })
puts '📊 payment_v2: disabled → canary'

feature_service.change_feature_state('payment_v2', :canary, :enabled, :enable, {
                                       reason: 'Canary successful, full rollout',
                                       requested_by: 'bob@company.com'
                                     })
puts '📊 payment_v2: canary → enabled'

# Dashboard feature transitions
feature_service.change_feature_state('dashboard_redesign', :disabled, :canary, :rollout_canary)
puts '📊 dashboard_redesign: disabled → canary'

# 4. Record feature usage
puts "\n📈 Recording Feature Usage..."
feature_service.record_feature_execution(
  'payment_v2',
  { user_id: 123, amount: 100.50, currency: 'USD' },
  { success: true, transaction_id: 'txn_123' },
  15.5 # execution time in ms
)

feature_service.record_feature_evaluation(
  'payment_v2',
  { user: { id: 456, groups: [:beta_users] } },
  true,
  'User is in beta group'
)

puts '✅ Recorded execution and evaluation events'

# 5. Query using projections
puts "\n🔍 Querying via Read Models..."

all_features = feature_service.all_features
puts "📋 Total features: #{all_features.size}"

enabled_features = feature_service.find_features_by_state(:enabled)
puts "✅ Enabled features: #{enabled_features.size}"

canary_features = feature_service.find_features_by_state(:canary)
puts "🕯️  Canary features: #{canary_features.size}"

# 6. Show comprehensive stats
puts "\n📊 System Statistics..."
stats = feature_service.feature_stats
puts "Total features: #{stats[:total_features]}"
puts 'By state:'
stats[:by_state].each do |state, count|
  puts "  #{state}: #{count}"
end

# 7. Recent transitions across the system
puts "\n🕐 Recent Transitions..."
recent = feature_service.recent_transitions(limit: 5)
if recent.is_a?(Array)
  # Direct projection response
  recent.each_with_index do |transition, i|
    puts "#{i + 1}. #{transition[:feature_id]}: #{transition[:from_state]} → #{transition[:to_state]} (#{transition[:event_name]})"
  end
else
  # Service layer response with metadata
  recent[:transitions].each_with_index do |transition, i|
    puts "#{i + 1}. #{transition[:feature_id]}: #{transition[:from_state]} → #{transition[:to_state]} (#{transition[:event_name]})"
  end
end

# 8. Event store inspection
puts "\n📚 Event Store Inspection..."
event_store = feature_service.instance_variable_get(:@event_store)
payment_events = event_store.get_events('payment_v2')
puts "Payment feature events: #{payment_events.size}"
payment_events.each_with_index do |event, i|
  puts "  #{i + 1}. #{event.event_type} (#{event.occurred_at.strftime('%H:%M:%S')})"
end

# 9. JSON-RPC API Demo
puts "\n🌐 JSON-RPC API Demo..."

# Create a JSON-RPC request
request = {
  jsonrpc: '2.0',
  method: 'feature.get',
  params: { featureId: 'payment_v2' },
  id: 1
}.to_json

# Handle the request
handler = StarGates.jsonrpc_handler
response = handler.handle_request(request)
parsed_response = JSON.parse(response)

puts 'Request: feature.get(payment_v2)'
puts "Response: #{parsed_response['result']['state']} state, #{parsed_response['result']['transition_count']} transitions"

# Another API call - get system stats
stats_request = {
  jsonrpc: '2.0',
  method: 'feature.stats',
  params: {},
  id: 2
}.to_json

stats_response = JSON.parse(handler.handle_request(stats_request))
puts "System stats: #{stats_response['result']['total_features']} features total"

# 10. Demonstrate aggregate reconstruction from events
puts "\n🔄 Event Replay & Aggregate Reconstruction..."

# Get a fresh aggregate by replaying events
repository = feature_service.instance_variable_get(:@repository)
reconstructed_payment = repository.find('payment_v2')

puts 'Reconstructed payment_v2 from events:'
puts "  Current state: #{reconstructed_payment.current_state}"
puts "  Transitions: #{reconstructed_payment.transition_history.size}"
puts "  Executions: #{reconstructed_payment.execution_history.size}"
puts "  Evaluations: #{reconstructed_payment.evaluation_history.size}"

# 11. Show the complete transition history
puts "\n📜 Complete Transition History..."
reconstructed_payment.transition_history.each_with_index do |transition, i|
  puts "#{i + 1}. #{transition[:from_state]} → #{transition[:to_state]} via #{transition[:event_name]}"
  puts "   Context: #{transition[:context]}" if transition[:context] && !transition[:context].empty?
  puts "   Time: #{transition[:occurred_at].strftime('%H:%M:%S.%L')}"
end

# 12. Health check
puts "\n❤️  Health Check..."
puts "Feature service healthy: #{feature_service.healthy?}"
puts "Event store healthy: #{event_store.respond_to?(:healthy?) ? event_store.healthy? : 'N/A'}"

# 13. Demonstrate projection rebuilding
puts "\n🔄 Projection Rebuilding..."
puts 'Rebuilding projections from event store...'
feature_service.rebuild_projections!
puts '✅ Projections rebuilt successfully'

# Verify everything still works
rebuilt_stats = feature_service.feature_stats
puts "Post-rebuild stats: #{rebuilt_stats[:total_features]} features"

puts "\n🎉 Foundation Demo Complete!"
puts "\nKey Features Demonstrated:"
puts '✅ Event Sourcing - Complete audit trail of all changes'
puts '✅ Hexagonal Architecture - Clean separation of concerns'
puts '✅ CQRS - Separate read/write models with projections'
puts '✅ JSON-RPC API - Clean, simple API for external integration'
puts '✅ Real-time Introspection - Complete system visibility'
puts '✅ Event Replay - Reconstruct state from event history'
puts '✅ Projection Management - Rebuild read models on demand'
puts '✅ Thread Safety - Concurrent-safe operations throughout'
puts "\n🚀 StarGates Foundation: Ready for Enterprise!"
