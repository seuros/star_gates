# frozen_string_literal: true

require_relative 'base_ship'
require_relative 'spaceflight_systems'

class Spaceship < BaseShip
  def engage_warp(destination, **context)
    activate(:warp_drive, **context) { SpaceflightSystems::WarpDrive.engage(destination) }
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
    define_system(:warp_drive, policy(3, seconds(60), seconds(30)),
                  group: :pilots, fallback: method(:emergency_propulsion))
    define_system(:fusion_reactor, policy(2, seconds(30), seconds(45)), retry_policy(2),
                  fallback: method(:backup_power_supply))
    define_system(:navigation_computer, policy(5, seconds(120), seconds(20)),
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
