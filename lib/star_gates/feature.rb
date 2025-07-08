# frozen_string_literal: true

require 'state_machines'
require 'concurrent'

module StarGates
  class Feature
    attr_reader :rollout_percentage, :group_matcher

    def initialize(rollout: 0, group: nil)
      @rollout_percentage = parse_rollout(rollout)
      @group_matcher = group
      @created_at = Time.now
      @transition_history = Concurrent::Array.new
      super()
    end

    # State machine for feature lifecycle
    state_machine :status, initial: :disabled do
      # State: Disabled - Feature is completely off
      state :disabled do
        def execute(context = {})
          StarGates.instrument('feature_disabled', feature: self.class.name, context: context)
          nil
        end

        def ui_component(_context = {})
          'default_component'
        end

        def config_value(key, _context = {})
          default_config[key]
        end
      end

      # State: Enabled - Feature is fully rolled out
      state :enabled do
        def execute(context = {})
          StarGates.instrument('feature_enabled', feature: self.class.name, context: context)
          if block_given?
            yield
          else
            true
          end
        end

        def ui_component(_context = {})
          'feature_component'
        end

        def config_value(key, _context = {})
          feature_config[key]
        end
      end

      # State: Canary - Feature is in gradual rollout
      state :canary do
        def execute(context = {})
          if eligible_for_rollout?(context)
            StarGates.instrument('feature_canary_enabled', feature: self.class.name, context: context)
            if block_given?
              yield
            else
              true
            end
          else
            StarGates.instrument('feature_canary_disabled', feature: self.class.name, context: context)
            nil
          end
        end

        def ui_component(context = {})
          if eligible_for_rollout?(context)
            'feature_component'
          else
            'default_component'
          end
        end

        def config_value(key, context = {})
          if eligible_for_rollout?(context)
            feature_config[key]
          else
            default_config[key]
          end
        end
      end

      # Events for state transitions
      event :enable do
        transition %i[disabled canary] => :enabled
      end

      event :disable do
        transition %i[enabled canary] => :disabled
      end

      event :rollout_canary do
        transition %i[disabled enabled] => :canary
      end

      # Transition tracking callbacks
      after_transition any => any do |feature, transition|
        feature.send(:record_transition, transition)
      end
    end

    def enabled_for?(context = {})
      case status
      when 'enabled'
        true
      when 'canary'
        eligible_for_rollout?(context)
      else
        false
      end
    end

    def enabled?
      !disabled?
    end

    # Check if user is eligible for rollout based on percentage and group
    def eligible_for_rollout?(context = {})
      return group_matches?(context) if group_matcher
      return false if rollout_percentage.zero?
      return true if rollout_percentage == 100

      user_id = extract_user_id(context)
      return false unless user_id

      user_hash = hash_user_id(user_id)
      (user_hash % 100) < rollout_percentage
    end

    # Configuration methods for state-specific behavior
    def feature_config
      @feature_config ||= {}
    end

    def default_config
      @default_config ||= {}
    end

    # ============================================================================
    # INTROSPECTION METHODS
    # ============================================================================

    # Get current rollout statistics
    def stats
      {
        name: self.class.name,
        status: status,
        status_name: status_name,
        rollout_percentage: rollout_percentage,
        group_matcher: group_matcher_info,
        created_at: @created_at,
        state_duration: state_duration,
        total_transitions: transition_count
      }
    end

    # Get complete feature configuration
    def configuration
      {
        rollout_percentage: rollout_percentage,
        group_matcher: group_matcher,
        feature_config: feature_config.dup,
        default_config: default_config.dup,
        state_machine_config: state_machine_config
      }
    end

    # Human-readable feature status summary
    def summary
      case status
      when 'disabled'
        "Feature '#{feature_name}' is DISABLED. No users have access."
      when 'enabled'
        "Feature '#{feature_name}' is ENABLED for all users (100% rollout)."
      when 'canary'
        if group_matcher
          "Feature '#{feature_name}' is in CANARY mode for group #{group_matcher} (#{rollout_percentage}% rollout)."
        else
          "Feature '#{feature_name}' is in CANARY mode with #{rollout_percentage}% rollout."
        end
      else
        "Feature '#{feature_name}' is in unknown state: #{status}."
      end
    end

    # Complete introspection data export
    def to_h
      {
        name: feature_name,
        class: self.class.name,
        status: status,
        stats: stats,
        configuration: configuration,
        summary: summary,
        introspected_at: Time.now
      }
    end

    # Mock user struct for testing (Data.define is Ruby 3.2+)
    MockUser = Data.define(:id, :groups) unless defined?(self::MockUser)

    # Test what a specific user would experience
    def simulate_for_user(user_id:, user_groups: [])
      mock_user = MockUser.new(id: user_id, groups: user_groups)
      context = { user: mock_user }

      eligible = enabled_for?(context)
      ui_component_result = ui_component(context)

      {
        user_id: user_id,
        user_groups: user_groups,
        eligible: eligible,
        reason: eligibility_reason(context),
        ui_component: ui_component_result,
        would_execute: eligible,
        feature_status: status
      }
    end

    # Debug why a user is or isn't eligible
    def eligibility_debug(user:)
      context = { user: user }
      user_id = extract_user_id(context)

      debug_info = {
        user_id: user_id,
        feature_status: status,
        rollout_percentage: rollout_percentage,
        group_matcher: group_matcher,
        eligible: enabled_for?(context)
      }

      case status
      when 'disabled'
        debug_info[:reason] = 'Feature is disabled'
      when 'enabled'
        debug_info[:reason] = 'Feature is fully enabled'
      when 'canary'
        if group_matcher
          group_match = group_matches?(context)
          debug_info[:group_match] = group_match
          debug_info[:reason] = group_match ? 'User matches group criteria' : 'User does not match group criteria'
        elsif user_id
          user_hash = hash_user_id(user_id)
          debug_info[:user_hash] = user_hash
          debug_info[:hash_modulo] = user_hash % 100
          debug_info[:reason] = if (user_hash % 100) < rollout_percentage
                                  "User hash #{user_hash % 100} is within rollout #{rollout_percentage}%"
                                else
                                  "User hash #{user_hash % 100} is outside rollout #{rollout_percentage}%"
                                end
        else
          debug_info[:reason] = 'No user ID found in context'
        end
      end

      debug_info
    end

    # Test different rollout scenarios
    def test_rollout_scenarios(percentages, sample_user_ids: (1..1000).to_a.sample(100))
      scenarios = {}

      percentages.each do |percentage|
        eligible_count = 0
        sample_user_ids.each do |user_id|
          user_hash = hash_user_id(user_id)
          eligible_count += 1 if (user_hash % 100) < percentage
        end

        scenarios[percentage] = {
          percentage: percentage,
          sample_size: sample_user_ids.size,
          eligible_users: eligible_count,
          estimated_percentage: (eligible_count.to_f / sample_user_ids.size * 100).round(2)
        }
      end

      scenarios
    end

    # Get transition history for this feature
    def transition_history(limit: 10)
      {
        feature_name: feature_name,
        total_transitions: @transition_history.size,
        transitions: @transition_history.last(limit).reverse.map do |transition|
          {
            timestamp: transition[:timestamp],
            from_state: transition[:from_state],
            to_state: transition[:to_state],
            event: transition[:event],
            feature_name: transition[:feature_name],
            feature_class: transition[:feature_class],
            duration_since: Time.now - transition[:timestamp]
          }
        end,
        limit: limit
      }
    end

    # Helper methods for introspection
    def feature_name
      @feature_name ||= self.class.name&.split('::')&.last || 'UnnamedFeature'
    end

    # Get transition count
    def transition_count
      @transition_history.size
    end

    private

    def group_matcher_info
      case group_matcher
      when Symbol
        { type: 'symbol', value: group_matcher }
      when Proc
        { type: 'proc', value: '<Proc>' }
      when nil
        nil
      else
        { type: group_matcher.class.name, value: group_matcher.to_s }
      end
    end

    def state_duration
      last_transition = @transition_history.last
      return 'No transitions yet' unless last_transition

      duration = Time.now - last_transition[:timestamp]
      if duration < 60
        "#{duration.round(1)}s"
      elsif duration < 3600
        "#{(duration / 60).round(1)}m"
      else
        "#{(duration / 3600).round(1)}h"
      end
    end

    def state_machine_config
      # Extract state machine configuration
      machine = self.class.state_machines[:status]
      return {} unless machine

      initial_state_obj = machine.initial_state(self)
      initial_state = initial_state_obj.respond_to?(:name) ? initial_state_obj.name : initial_state_obj

      {
        initial_state: initial_state,
        states: machine.states.map(&:name),
        events: machine.events.map(&:name)
      }
    end

    def eligibility_reason(context)
      case status
      when 'disabled'
        'Feature is disabled'
      when 'enabled'
        'Feature is fully enabled'
      when 'canary'
        eligible_for_rollout?(context) ? 'User is eligible for rollout' : 'User is not eligible for rollout'
      else
        "Unknown status: #{status}"
      end
    end

    def parse_rollout(rollout)
      case rollout
      when Numeric then rollout.to_i
      when String then rollout.delete_suffix('%').to_i
      else 0
      end
    end

    def group_matches?(context)
      return false unless group_matcher

      user = context[:user]
      return false unless user

      case group_matcher
      when Symbol
        user.respond_to?(:groups) && user.groups.include?(group_matcher)
      when Proc
        group_matcher.call(user)
      else
        false
      end
    end

    def extract_user_id(context)
      user = context[:user]
      return nil unless user

      if user.respond_to?(:id)
        user.id
      elsif user.respond_to?(:user_id)
        user.user_id
      elsif user.is_a?(String) || user.is_a?(Integer)
        user
      end
    end

    def hash_user_id(user_id)
      user_id.to_s.hash.abs
    end

    # Record state transition with timestamp and metadata
    def record_transition(transition)
      # Convert state values to symbols for consistency
      from_state = transition.from.is_a?(String) ? transition.from.to_sym : transition.from
      to_state = transition.to.is_a?(String) ? transition.to.to_sym : transition.to

      transition_record = {
        timestamp: Time.now,
        from_state: from_state,
        to_state: to_state,
        event: transition.event,
        feature_name: feature_name,
        feature_class: self.class.name
      }

      @transition_history << transition_record

      # Keep only the last 50 transitions to prevent memory bloat
      return unless @transition_history.size > 50

      @transition_history.replace(@transition_history.last(50))
    end
  end

  class PercentageHelper
    def self.percent(value)
      value
    end
  end
end
