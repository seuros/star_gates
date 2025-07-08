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
    define_system(:scanner, threshold: 1, within: 10.seconds, reset_after: 5.seconds,
                  fallback: -> { 'Using archived planetary charts' })
    define_system(:probe_launcher, threshold: 3, within: 1.minute, reset_after: 30.seconds,
                  fallback: -> { 'Probe launch postponed' })
  end
end
