# frozen_string_literal: true

require_relative 'base_spaceship'

class ExplorerShip < BaseSpaceship
  def scan_planet
    activate(:scanner) { 'Planet scanned' }
  end

  def launch_probe
    activate(:probe_launcher) { 'Probe launched' }
  end

  protected

  def configure_gates
    super
    define_system(:scanner, policy(1, seconds(10), seconds(5)),
                  fallback: -> { 'Using archived planetary charts' })
    define_system(:probe_launcher, policy(3, seconds(60), seconds(30)),
                  fallback: -> { 'Probe launch postponed' })
  end
end
