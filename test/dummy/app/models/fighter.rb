# frozen_string_literal: true

require_relative 'base_spaceship'

class Fighter < BaseSpaceship
  def fire_lasers
    activate(:weapons) { 'Lasers fired' }
  end

  protected

  def configure_gates
    super
    define_system(:weapons, policy(2, seconds(30), seconds(20)),
                  fallback: -> { 'Manual targeting' })
  end
end
