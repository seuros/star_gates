# frozen_string_literal: true

require_relative 'base_ship'
require_relative 'spaceflight_systems'

class Spaceship < BaseShip
  def engage_warp(destination, pilot: nil)
    activate(:warp_drive, user: pilot) { SpaceflightSystems::WarpDrive.engage(destination) }
  end

  def power_up_reactor(level = 100)
    activate(:fusion_reactor) { SpaceflightSystems::FusionReactor.ignite(level) }
  end

  def calculate_route(coordinates)
    activate(:navigation_computer) { SpaceflightSystems::NavigationComputer.calculate_route(coordinates) }
  end

  protected

  def configure_gates
    super
    define_system(:warp_drive, group: :pilots, threshold: 3, within: 1.minute, reset_after: 30.seconds,
                  fallback: method(:emergency_propulsion))
    define_system(:fusion_reactor, threshold: 2, within: 30.seconds, reset_after: 45.seconds,
                  retry_config: { max_attempts: 2, base_delay: 0.001 },
                  fallback: method(:backup_power_supply))
    define_system(:navigation_computer, threshold: 5, within: 2.minutes, reset_after: 20.seconds,
                  fallback: method(:manual_navigation))
  end

  def emergency_propulsion
    log_event('Engaging emergency thrusters')
    { status: 'emergency_mode', speed: 'impulse_only' }
  end

  def backup_power_supply
    log_event('Switching to auxiliary power')
    { status: 'auxiliary', power_output: 40, temperature: 'stable' }
  end

  def manual_navigation
    log_event('Switching to manual navigation')
    { route: 'manual', distance: 'unknown', eta: 'calculating...' }
  end
end
