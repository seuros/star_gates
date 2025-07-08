# frozen_string_literal: true

# Deterministic simulated hardware. Real adapters must enforce their own IO timeouts.
module SpaceflightSystems
  class WarpDriveError < StandardError; end
  class ReactorOverloadError < StandardError; end
  class NavigationSystemOfflineError < StandardError; end

  class WarpDrive
    def self.engage(destination)
      raise WarpDriveError, 'Subspace interference' if destination == :unstable_sector

      { status: 'engaged', destination: destination, speed: 'warp_9' }
    end
  end

  class FusionReactor
    def self.ignite(power_level)
      raise ReactorOverloadError, 'Unsafe power level' if power_level > 100

      { status: 'online', power_output: power_level, temperature: 'optimal' }
    end
  end

  class NavigationComputer
    def self.calculate_route(coordinates)
      unless coordinates.is_a?(Array) && coordinates.size == 3 && coordinates.all?(Numeric)
        raise NavigationSystemOfflineError, 'Three numeric coordinates required'
      end

      { route: 'calculated', distance: '42.7 parsecs', eta: '3.2 hours' }
    end
  end
end
