# frozen_string_literal: true

require_relative 'base_spaceship'

class CorellianFreighter < BaseSpaceship
  def load_cargo
    activate(:cargo_bay) { 'Cargo loaded' }
  end

  protected

  def configure_gates
    super
    define_system(:cargo_bay, policy(10, seconds(300), seconds(120)),
                  fallback: -> { 'Cargo handling paused' })
    define_system(:engine, policy(5, seconds(120), seconds(60)),
                  fallback: -> { 'Auxiliary thrusters' })
  end
end
