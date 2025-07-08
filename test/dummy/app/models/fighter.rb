# frozen_string_literal: true

require_relative 'base_spaceship'

class Fighter < BaseSpaceship
  def fire_lasers
    activate(:weapons) { 'Lasers fired' }
  end

  protected

  def configure_gates
    super
    define_system(:weapons, threshold: 2, within: 30.seconds, reset_after: 20.seconds,
                  fallback: -> { 'Manual targeting' })
  end
end
