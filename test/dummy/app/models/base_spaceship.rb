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
    define_system(:engine, policy(3, seconds(60), seconds(30)),
                  fallback: -> { 'Emergency power' })
    define_system(:shields, policy(5, seconds(120), seconds(45)),
                  fallback: -> { 'Emergency deflectors' })
  end
end
