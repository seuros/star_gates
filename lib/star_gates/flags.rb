# frozen_string_literal: true

module StarGates
  # Boolean flags with environment > configuration > runtime > false precedence.
  # Runtime state uses Feature's lifecycle and is local to this process.
  class Flags
    attr_accessor :configuration

    def initialize(env: ENV, configuration: {})
      @env = env
      @configuration = configuration
      @runtime = {}
      @mutex = Mutex.new
    end

    def enabled?(name)
      debug(name)[:enabled]
    end

    def set(name, value)
      update(name, value)
    end

    def enable(name, metadata: {})
      update(name, true, metadata: metadata)
    end

    def disable(name)
      update(name, false)
    end

    def enable_if(name)
      set(name, yield)
    end

    def remove(name)
      @mutex.synchronize { @runtime.delete(normalize(name)) }
      nil
    end

    def reset!
      @mutex.synchronize { @runtime.clear }
      nil
    end

    def all
      configured = configuration_flags
      names = (environment_flags.keys + configured.keys + runtime_names).uniq
      names.to_h { |name| [name, resolution(name, configured).slice(:enabled, :source)] }
    end

    def enabled_flags
      all.select { |_, flag| flag[:enabled] }.keys.map(&:to_sym)
    end

    def summary
      {
        runtime_flags: runtime_names.map(&:to_sym),
        environment_flags: environment_flags.keys.map(&:to_sym),
        configuration_flags: configuration_flags.keys.map(&:to_sym),
        all_enabled: enabled_flags
      }
    end

    def debug(name)
      resolution(normalize(name), configuration_flags)
    end

    def flag_status(name)
      normalized = normalize(name)
      details = debug(normalized)
      metadata = @mutex.synchronize { @runtime[normalized]&.fetch(:metadata)&.dup || {} }
      { name: normalized&.to_sym, enabled: details[:enabled], source: details[:source], metadata: metadata }
    end

    private

    def normalize(name)
      return unless name.is_a?(String) || name.is_a?(Symbol)

      normalized = name.to_s.tr('-', '_').downcase
      normalized if normalized.match?(/\A[a-z0-9_]+\z/)
    end

    def boolean(value)
      value == true || (value.is_a?(String) && %w[true 1 yes on].include?(value.downcase))
    end

    def update(name, value, metadata: nil)
      normalized = normalize(name)
      raise ArgumentError, 'flag name must be a nonempty string or symbol' unless normalized

      enabled = boolean(value)
      @mutex.synchronize do
        entry = @runtime[normalized] ||= { feature: Feature.new, metadata: {} }
        feature = entry.fetch(:feature)
        feature.enable if enabled && feature.disabled?
        feature.disable if !enabled && !feature.disabled?
        entry[:metadata] = metadata.dup if metadata
      end
      enabled
    end

    def runtime_names
      @mutex.synchronize { @runtime.keys }
    end

    def configuration_flags
      values = configuration.is_a?(Proc) ? configuration.call : configuration
      raise ArgumentError, 'configuration must be a Hash or a Proc returning a Hash' unless values.is_a?(Hash)

      values.each_with_object({}) do |(name, value), flags|
        normalized = normalize(name)
        flags[normalized] = value if normalized && [true, false].include?(value)
      end
    end

    def environment_flags
      @env.each_pair.with_object({}) do |(key, value), flags|
        next unless key.start_with?('FEATURE_') && !value.to_s.strip.empty?

        name = normalize(key.delete_prefix('FEATURE_'))
        flags[name] = value if name && key == "FEATURE_#{name.upcase}"
      end
    end

    def resolution(name, configured)
      env_key = "FEATURE_#{name&.upcase}"
      environment_value = name && @env[env_key]
      runtime_value = @mutex.synchronize { @runtime[name]&.fetch(:feature)&.enabled_for? }

      value, source = if name && !environment_value.to_s.strip.empty?
                        [boolean(environment_value), "environment:#{env_key}"]
                      elsif configured.key?(name)
                        [configured.fetch(name), "config:#{name}"]
                      elsif !runtime_value.nil?
                        [runtime_value, 'runtime']
                      else
                        [false, 'default']
                      end

      {
        flag: name&.to_sym,
        enabled: value,
        value: value,
        source: source,
        environment_value: environment_value,
        configuration_value: configured[name],
        runtime_value: runtime_value
      }
    end
  end
end
