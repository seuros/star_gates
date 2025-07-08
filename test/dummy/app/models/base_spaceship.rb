# frozen_string_literal: true

require_relative 'base_ship'

class BaseSpaceship < BaseShip
  def start_engine
    activate(:engine) { 'Engine started' }
  end

  def raise_shields
    activate(:shields) { 'Shields up' }
  end

  protected

  def configure_gates
    super
    define_system(:engine, threshold: 3, within: 1.minute, reset_after: 30.seconds,
                  fallback: -> { 'Emergency power' })
    define_system(:shields, threshold: 5, within: 2.minutes, reset_after: 45.seconds,
                  fallback: -> { 'Emergency deflectors' })
  end
end
