# frozen_string_literal: true

require_relative 'base_spaceship'

class CorellianFreighter < BaseSpaceship
  def load_cargo
    activate(:cargo_bay) { 'Cargo loaded' }
  end

  protected

  def configure_gates
    super
    define_system(:cargo_bay, threshold: 10, within: 5.minutes, reset_after: 2.minutes,
                  fallback: -> { 'Cargo handling paused' })
    define_system(:engine, threshold: 5, within: 2.minutes, reset_after: 1.minute,
                  fallback: -> { 'Auxiliary thrusters' })
  end
end
