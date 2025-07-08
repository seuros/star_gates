# frozen_string_literal: true

require_relative '../../../lib/star_gates'

module StarGates
  module Examples
    # Comprehensive demonstration of StarGates introspection capabilities
    class IntrospectionDemo
      def self.run
        puts '🌌 StarGates Introspection Demo'
        puts '=' * 50

        demo = new
        demo.setup_features
        demo.demonstrate_feature_introspection
        demo.demonstrate_system_introspection
        demo.demonstrate_user_simulation
        demo.demonstrate_debugging
        demo.demonstrate_rollout_analysis
      end

      def setup_features
        puts "\n📊 Setting up demo features..."

        @payment_feature = StarGates::Feature.new(rollout: 25, group: :beta_users)
        @dashboard_feature = StarGates::Feature.new(rollout: 75)
        @experimental_feature = StarGates::Feature.new(rollout: 5)

        # Create gates
        @payment_gate = StarGates::Gate.new(:payment_v2, feature: @payment_feature)
        @dashboard_gate = StarGates::Gate.new(:dashboard_redesign, feature: @dashboard_feature)
        @experimental_gate = StarGates::Gate.new(:experimental_ai, feature: @experimental_feature)

        # Register gates
        StarGates.registry.register(:payment_v2, @payment_gate)
        StarGates.registry.register(:dashboard_redesign, @dashboard_gate)
        StarGates.registry.register(:experimental_ai, @experimental_gate)

        # Set different states
        @payment_feature.rollout_canary
        @dashboard_feature.enable
        # experimental stays disabled

        puts '✅ Created 3 features with different states and rollout settings'
      end

      def demonstrate_feature_introspection
        puts "\n🔍 Feature-Level Introspection"
        puts '-' * 30

        [@payment_feature, @dashboard_feature, @experimental_feature].each do |feature|
          puts "\n📋 Feature: #{feature.feature_name}"

          # Basic stats
          stats = feature.stats
          puts "  Status: #{stats[:status]} (#{stats[:status_name]})"
          puts "  Rollout: #{stats[:rollout_percentage]}%"
          puts "  Group: #{stats[:group_matcher] ? stats[:group_matcher][:value] : 'None'}"

          # Human-readable summary
          puts "  Summary: #{feature.summary}"

          # Configuration details
          config = feature.configuration
          puts "  Config: rollout=#{config[:rollout_percentage]}%, group=#{config[:group_matcher]}"
        end
      end

      def demonstrate_system_introspection
        puts "\n🌐 System-Level Introspection"
        puts '-' * 30

        # Feature overview
        overview = StarGates.feature_overview
        puts "\n📊 System Overview:"
        puts "  Total Gates: #{overview[:total_gates]}"
        puts "  Total Features: #{overview[:summary][:total_features]}"
        puts '  State Distribution:'
        overview[:summary][:by_status].each do |status, count|
          puts "    #{status}: #{count}"
        end

        # Rollout statistics
        stats = StarGates.rollout_statistics
        puts "\n📈 Rollout Statistics:"
        puts '  Features by Status:'
        stats[:features_by_status].each do |status, count|
          puts "    #{status}: #{count}"
        end
        puts "  Average Rollout: #{stats[:average_rollout]}%"
        puts '  Rollout Distribution:'
        stats[:rollout_distribution].each do |range, count|
          puts "    #{range}: #{count} features"
        end

        # State distribution with percentages
        distribution = StarGates.state_distribution
        puts "\n📊 State Distribution:"
        distribution[:distribution].each do |state, count|
          percentage = distribution[:percentages][state]
          puts "    #{state}: #{count} (#{percentage}%)"
        end
      end

      def demonstrate_user_simulation
        puts "\n👤 User Simulation & Testing"
        puts '-' * 30

        test_users = [
          { id: 123, groups: [:beta_users] },
          { id: 456, groups: [:regular] },
          { id: 789, groups: %i[admin beta_users] }
        ]

        test_users.each do |user_data|
          puts "\n🧪 Testing User ID: #{user_data[:id]} (Groups: #{user_data[:groups]})"

          [@payment_feature, @dashboard_feature].each do |feature|
            simulation = feature.simulate_for_user(
              user_id: user_data[:id],
              user_groups: user_data[:groups]
            )

            puts "  #{feature.feature_name}:"
            puts "    Eligible: #{simulation[:eligible]}"
            puts "    Reason: #{simulation[:reason]}"
            puts "    UI Component: #{simulation[:ui_component]}"
          end
        end
      end

      def demonstrate_debugging
        puts "\n🐛 Debugging & Troubleshooting"
        puts '-' * 30

        require 'ostruct'
        test_user = OpenStruct.new(id: 500, groups: [:regular])

        [@payment_feature, @dashboard_feature, @experimental_feature].each do |feature|
          puts "\n🔧 Debugging #{feature.feature_name}:"

          debug_info = feature.eligibility_debug(user: test_user)
          puts "  User ID: #{debug_info[:user_id]}"
          puts "  Feature Status: #{debug_info[:feature_status]}"
          puts "  Eligible: #{debug_info[:eligible]}"
          puts "  Reason: #{debug_info[:reason]}"

          puts "  User Hash: #{debug_info[:user_hash]} (mod 100: #{debug_info[:hash_modulo]})" if debug_info[:user_hash]

          puts "  Group Match: #{debug_info[:group_match]}" if debug_info[:group_match]
        end
      end

      def demonstrate_rollout_analysis
        puts "\n📈 Rollout Scenario Analysis"
        puts '-' * 30

        test_percentages = [10, 25, 50, 75, 100]

        [@dashboard_feature, @experimental_feature].each do |feature|
          puts "\n🎯 #{feature.feature_name} Rollout Analysis:"

          scenarios = feature.test_rollout_scenarios(test_percentages, sample_user_ids: (1..200).to_a)

          scenarios.each do |percentage, data|
            puts "  #{percentage}% rollout:"
            puts "    Estimated users: #{data[:eligible_users]}/#{data[:sample_size]}"
            puts "    Actual percentage: #{data[:estimated_percentage]}%"
          end
        end
      end

      private

      def logger
        @logger ||= defined?(Rails) ? Rails.logger : Logger.new($stdout, level: Logger::INFO)
      end
    end
  end
end

# Run the demo if this file is executed directly
StarGates::Examples::IntrospectionDemo.run if __FILE__ == $PROGRAM_NAME
