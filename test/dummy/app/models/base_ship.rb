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
    define_system(:life_support, policy(2, seconds(60), seconds(30)),
                  fallback: method(:activate_emergency_life_support))
    define_system(:navigation, policy(5, seconds(120), seconds(45)),
                  fallback: method(:engage_manual_navigation))
    define_system(:communications, policy(3, seconds(90), seconds(20)),
                  fallback: method(:use_emergency_beacon))
  end

  NS_PER_SECOND = 1_000_000_000

  def seconds(count) = count * NS_PER_SECOND

  # Opens after `threshold` failures within `within`, cools down for
  # `reset_after` (Integer nanoseconds), closes on the first good probe.
  def policy(threshold, within, reset_after)
    BreakerMachines::Policy.new(BreakerMachines::Threshold.new(threshold, nil, 0), within,
                                BreakerMachines::Recovery.new(reset_after, 0.0, 1, 1), nil)
  end

  # Up to `max_attempts` tries, a millisecond apart.
  def retry_policy(max_attempts)
    StarGates::RetryPolicy.new(ChronoMachines::Constant.new(1_000_000, 0.0), max_attempts)
  end

  def define_system(system, policy, retry_policy = nil, fallback:, rollout: 100, group: nil)
    # Include object_id so two ships never share rollout or circuit state.
    gate_name = :"#{registry_number}:#{object_id}:#{system}"
    fallback_action = fallback

    system_gate = StarGates.define do
      gate gate_name do
        feature rollout: rollout, group: group
        circuit policy, retry_policy
        run { |context| context.fetch(:operation).call }
        fallback { fallback_action.call }
      end
    end

    # StarGates features start disabled. Existing ship systems are explicitly
    # enabled; operators can later canary or disable each gate's feature.
    system_gate.feature.enable
    gates[system] = system_gate
  end

  def activate(system, **context, &operation)
    gate(system).call(**context, operation: operation)
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
