# frozen_string_literal: true

require_relative '../../../lib/star_gates'

module StarGates
  module Examples
    # Demonstrates the transition history tracking capabilities
    class TransitionDemo
      def self.run
        puts '🚀 StarGates Transition History Demo'
        puts '=' * 40

        demo = new
        demo.setup_features
        demo.demonstrate_transitions
        demo.show_transition_history
        demo.show_system_transitions
        demo.show_llm_introspection
      end

      def setup_features
        puts "\n📋 Setting up features..."

        # Create features with different configurations
        @payment_feature = StarGates::Feature.new(rollout: 25, group: :beta)
        @dashboard_feature = StarGates::Feature.new(rollout: 50)
        @ai_feature = StarGates::Feature.new(rollout: 0)

        puts '✅ Created 3 features'
        puts '   - Payment Feature (beta group)'
        puts '   - Dashboard Feature (50% rollout)'
        puts '   - AI Feature (0% rollout)'
      end

      def demonstrate_transitions
        puts "\n🔄 Demonstrating state transitions..."

        # Payment feature lifecycle
        puts "\n💳 Payment Feature transitions:"
        puts "   Initial state: #{@payment_feature.status}"

        @payment_feature.rollout_canary
        puts "   After rollout_canary: #{@payment_feature.status}"

        sleep(0.1) # Small delay to show time differences

        @payment_feature.enable
        puts "   After enable: #{@payment_feature.status}"

        sleep(0.1)

        @payment_feature.disable
        puts "   After disable: #{@payment_feature.status}"

        sleep(0.1)

        @payment_feature.enable
        puts "   After re-enable: #{@payment_feature.status}"

        # Dashboard feature lifecycle
        puts "\n📊 Dashboard Feature transitions:"
        puts "   Initial state: #{@dashboard_feature.status}"

        @dashboard_feature.rollout_canary
        puts "   After rollout_canary: #{@dashboard_feature.status}"

        sleep(0.1)

        @dashboard_feature.enable
        puts "   After enable: #{@dashboard_feature.status}"

        puts "\n🤖 AI Feature (no transitions):"
        puts "   State: #{@ai_feature.status}"
      end

      def show_transition_history
        puts "\n📚 Individual Feature Transition History"
        puts '-' * 40

        [@payment_feature, @dashboard_feature, @ai_feature].each do |feature|
          puts "\n🔍 #{feature.feature_name} History:"
          puts "   Total transitions: #{feature.transition_count}"
          puts "   Current state: #{feature.status}"
          puts "   Time in current state: #{feature.send(:state_duration)}"

          if feature.transition_count.positive?
            puts '   Recent transitions:'
            feature.transition_history(limit: 5)[:transitions].each_with_index do |transition, i|
              puts "     #{i + 1}. #{transition[:from_state]} → #{transition[:to_state]} (#{transition[:event]})"
              timestamp = transition[:timestamp].strftime('%H:%M:%S.%L')
              puts "        #{timestamp} - #{transition[:duration_since].round(3)}s ago"
            end
          else
            puts '   No transitions recorded'
          end
        end
      end

      def show_system_transitions
        puts "\n🌍 System-wide Recent Transitions"
        puts '-' * 40

        # Create gates for system-level tracking
        payment_gate = StarGates::Gate.new(:payment_v2, feature: @payment_feature)
        dashboard_gate = StarGates::Gate.new(:dashboard_redesign, feature: @dashboard_feature)
        ai_gate = StarGates::Gate.new(:ai_assistant, feature: @ai_feature)

        # Register gates
        StarGates.registry.register(:payment_v2, payment_gate)
        StarGates.registry.register(:dashboard_redesign, dashboard_gate)
        StarGates.registry.register(:ai_assistant, ai_gate)

        recent_transitions = StarGates.recent_transitions(limit: 10)

        puts '📊 System Summary:'
        puts "   Total transitions found: #{recent_transitions[:total_found]}"
        puts "   Showing: #{recent_transitions[:transitions].size}"
        puts "   Generated at: #{recent_transitions[:generated_at].strftime('%H:%M:%S')}"

        if recent_transitions[:transitions].any?
          puts "\n🕐 Recent Transitions (newest first):"
          recent_transitions[:transitions].each_with_index do |transition, i|
            puts "   #{i + 1}. #{transition[:feature_name]}: #{transition[:from_state]} → #{transition[:to_state]}"
            puts "      Event: #{transition[:event]}"
            timestamp = transition[:timestamp].strftime('%H:%M:%S.%L')
            puts "      When: #{timestamp} (#{transition[:duration_since].round(3)}s ago)"
            puts ''
          end
        end

        # Show system overview
        overview = StarGates.feature_overview
        puts '📈 System Overview:'
        puts "   Total gates: #{overview[:total_gates]}"
        puts '   Features by status:'
        overview[:summary][:by_status].each do |status, count|
          puts "     #{status}: #{count}"
        end
      end

      def show_llm_introspection
        puts "\n🤖 LLM-Friendly Introspection Data"
        puts '-' * 40

        # Generate comprehensive introspection data
        introspection_data = {
          timestamp: Time.now,
          system_overview: StarGates.feature_overview,
          rollout_statistics: StarGates.rollout_statistics,
          recent_transitions: StarGates.recent_transitions(limit: 5),
          feature_details: {
            payment_v2: @payment_feature.to_h,
            dashboard_redesign: @dashboard_feature.to_h,
            ai_assistant: @ai_feature.to_h
          }
        }

        puts '📊 Generated comprehensive introspection data:'
        puts '   System overview: ✅'
        puts '   Rollout statistics: ✅'
        puts '   Recent transitions: ✅'
        puts '   Feature details: ✅'
        puts "   Total data size: #{introspection_data.to_s.size} chars"

        # Show a sample of what LLM would see
        puts "\n🔍 Sample LLM Data (Payment Feature):"
        payment_data = introspection_data[:feature_details][:payment_v2]
        puts "   Name: #{payment_data[:name]}"
        puts "   Status: #{payment_data[:status]}"
        puts "   Summary: #{payment_data[:summary]}"
        puts "   Transitions: #{payment_data[:stats][:total_transitions]}"
        puts "   Configuration: #{payment_data[:configuration][:rollout_percentage]}% rollout"

        puts "\n✨ All introspection data is structured and ready for LLM analysis!"
      end
    end
  end
end

# Run the demo if this file is executed directly
StarGates::Examples::TransitionDemo.run if __FILE__ == $PROGRAM_NAME
