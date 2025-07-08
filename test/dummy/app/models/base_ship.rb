# frozen_string_literal: true

require_relative '../../../../lib/star_gates'

# Example adapter, not a new gem API. Every subsystem is a real StarGates::Gate.
class BaseShip
  attr_reader :name, :registry_number, :captain_log, :gates

  def initialize(name = self.class.name, registry_number = nil)
    @name = name
    @registry_number = registry_number || "#{self.class.name}-#{object_id}"
    @captain_log = []
    @gates = {}
    configure_gates
  end

  def gate(system)
    gates.fetch(system.to_sym)
  end

  def activate_life_support
    activate(:life_support) { 'Life support active at 100%' }
  end

  def calculate_course(destination)
    activate(:navigation) { "Course plotted to #{destination}" }
  end

  def send_message(message)
    activate(:communications) { "Message sent: #{message}" }
  end

  protected

  def configure_gates
    define_system(:life_support, threshold: 2, within: 1.minute, reset_after: 30.seconds,
                  fallback: method(:activate_emergency_life_support))
    define_system(:navigation, threshold: 5, within: 2.minutes, reset_after: 45.seconds,
                  fallback: method(:engage_manual_navigation))
    define_system(:communications, threshold: 3, within: 90.seconds, reset_after: 20.seconds,
                  fallback: method(:use_emergency_beacon))
  end

  def define_system(system, fallback:, rollout: 100, group: nil, **circuit_config)
    # Include object_id so two ships never share rollout or circuit state.
    gate_name = :"#{registry_number}:#{object_id}:#{system}"
    fallback_action = fallback

    system_gate = StarGates.define do
      gate gate_name do
        feature rollout: rollout, group: group
        circuit(**circuit_config)
        run { |context| context.fetch(:operation).call }
        fallback { fallback_action.call }
      end
    end

    # StarGates features start disabled. Existing ship systems are explicitly
    # enabled; operators can later canary or disable each gate's feature.
    system_gate.feature.enable
    gates[system] = system_gate
  end

  def activate(system, user: nil, &operation)
    gate(system).call(user: user, operation: operation)
  end

  def log_event(message)
    captain_log << "[#{Time.now.strftime('%H:%M:%S')}] #{message}"
  end

  def activate_emergency_life_support
    log_event('Emergency life support activated')
    'Emergency oxygen reserves online'
  end

  def engage_manual_navigation
    log_event('Switching to manual navigation')
    'Manual navigation engaged'
  end

  def use_emergency_beacon
    log_event('Emergency beacon activated')
    'SOS beacon transmitting'
  end
end
