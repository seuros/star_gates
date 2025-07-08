# frozen_string_literal: true

require 'singleton'
require_relative 'science_vessel'

# Royal Martian Navy Ship Atlas Monkey
# The legendary vessel with the Universal Commentary Engine
# Only one can exist in the universe at any given time
class RMNSAtlasMonkey < ScienceVessel
  include Singleton

  attr_reader :commentary_log, :wisdom_level

  def initialize
    super('RMNS Atlas Monkey', 'RMN-2142')
    @commentary_log = []
    @wisdom_level = 9000 # It's over 9000!
    @universal_truths = [
      'In space, no one can hear you debug.',
      'The answer is 42, but what was the question?',
      'Have you tried turning the universe off and on again?',
      "Space is big. Really big. You just won't believe how vastly, hugely, mind-bogglingly big it is.",
      "The ships hung in the sky in much the same way that bricks don't.",
      "Don't panic!",
      'Time is an illusion. Lunchtime doubly so.',
      'Flying is learning how to throw yourself at the ground and miss.',
      'The Universe is not only queerer than we suppose, but queerer than we CAN suppose.',
      'Any sufficiently advanced technology is indistinguishable from magic.'
    ]
  end

  def provide_commentary(situation)
    activate(:universal_commentary_engine) do
      wisdom = generate_profound_wisdom(situation)
      @commentary_log << { time: Time.now, situation: situation, wisdom: wisdom }
      wisdom
    end
  end

  def analyze_meaning_of_life
    activate(:universal_commentary_engine) do
      activate(:sensor_array) do
        @wisdom_level += 1
        "After deep analysis: 42. But also, #{@universal_truths.sample}"
      end
    end
  end

  def scan_for_irony(observation)
    activate(:sensor_array) do
      activate(:universal_commentary_engine) do
        irony_level = observation.length % 10
        commentary = case irony_level
                     when 0..3
                       'No irony detected. How ironic.'
                     when 4..6
                       'Moderate irony levels. The universe chuckles.'
                     when 7..9
                       'High irony detected! The cosmos is having a laugh.'
                     end

        provide_commentary("Irony scan of: #{observation}")
        commentary
      end
    end
  end

  def contemplate_existence
    activate(:laboratory) do
      activate(:universal_commentary_engine) do
        thought = @universal_truths.sample
        @wisdom_level += 0.1
        log_event("Contemplation complete. Wisdom level: #{@wisdom_level}")
        "I think, therefore I am... a spaceship. #{thought}"
      end
    end
  end

  def recent_commentary(count = 5)
    @commentary_log.last(count).map do |entry|
      "[#{entry[:time].strftime('%H:%M:%S')}] #{entry[:situation]}: #{entry[:wisdom]}"
    end
  end

  # Override the probe launcher to add commentary
  def launch_probe(target)
    result = super
    provide_commentary("Launching probe at #{target}")
    result
  end

  protected

  def configure_gates
    super
    define_system(:universal_commentary_engine, threshold: 42, within: 420.seconds, reset_after: 3.14159.seconds,
                  fallback: method(:provide_generic_wisdom))
    define_system(:sensor_array, threshold: 1, within: 30.seconds, reset_after: 90.seconds,
                  fallback: method(:use_intuition))
  end

  def generate_profound_wisdom(situation)
    words = situation.downcase.split

    if words.include?('error') || words.include?('failure')
      'Failure is just success in progress. Also, check your logs.'
    elsif words.include?('success')
      'Success is 90% preparation and 10% not breaking the circuit breakers.'
    elsif words.include?('quantum')
      'In the quantum realm, the circuit is both open AND closed until observed.'
    elsif words.include?('time')
      'Time flies like an arrow; fruit flies like a banana.'
    else
      @universal_truths.sample
    end
  end

  def provide_generic_wisdom
    log_event('Commentary Engine offline - dispensing emergency wisdom')
    [
      'When in doubt, add more circuit breakers.',
      'The real treasure was the circuits we broke along the way.',
      'Have you considered that maybe the bug is a feature?',
      'In an infinite universe, all edge cases exist simultaneously.'
    ].sample
  end

  def use_intuition
    log_event('Sensors offline - using pure intuition')
    "My spider-sense is tingling... or maybe that's just a loose wire."
  end
end

# Convenience method to access the one true Atlas Monkey
def atlas_monkey
  RMNSAtlasMonkey.instance
end
