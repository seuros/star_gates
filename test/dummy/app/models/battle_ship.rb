# frozen_string_literal: true

require_relative 'base_ship'

class BattleShip < BaseShip
  attr_reader :weapon_systems, :shield_strength

  def initialize(name, registry_number)
    super
    @weapon_systems = %i[phasers photon_torpedoes quantum_torpedoes]
    @shield_strength = 100
  end

  def fire_phasers(target)
    activate(:weapons) do
      activate(:targeting_computer) do
        @shield_strength -= 2
        "Phasers fired at #{target} - Direct hit!"
      end
    end
  end

  def fire_torpedoes(target, type = :photon)
    activate(:weapons) do
      raise 'Invalid torpedo type' unless weapon_systems.include?(:"#{type}_torpedoes")

      "#{type.to_s.capitalize} torpedoes launched at #{target}"
    end
  end

  def raise_shields
    activate(:shields) do
      @shield_strength = 100
      'Shields at maximum strength'
    end
  end

  def tactical_analysis(enemy_ship)
    activate(:targeting_computer) { "Analysis complete: #{enemy_ship} shows weakness in aft shields" }
  end

  protected

  def configure_gates
    super
    define_system(:weapons, threshold: 2, within: 30.seconds, reset_after: 20.seconds,
                  fallback: method(:engage_backup_weapons))
    define_system(:shields, threshold: 1, within: 1.minute, reset_after: 45.seconds,
                  fallback: method(:divert_power_to_hull_plating))
    define_system(:targeting_computer, threshold: 3, within: 45.seconds, reset_after: 30.seconds,
                  fallback: method(:use_manual_targeting))
    define_system(:navigation, threshold: 10, within: 2.minutes, reset_after: 15.seconds,
                  fallback: method(:engage_evasive_pattern))
  end

  def engage_backup_weapons
    log_event('Switching to backup weapon systems')
    'Manual weapons control engaged'
  end

  def divert_power_to_hull_plating
    log_event('Diverting power to ablative hull plating')
    'Hull plating reinforced - 30% protection'
  end

  def use_manual_targeting
    log_event('Manual targeting engaged')
    'Targeting manually - accuracy reduced'
  end

  def engage_evasive_pattern
    log_event('Executing evasive pattern Delta-5')
    'Evasive maneuvers engaged'
  end
end
