# frozen_string_literal: true

module StarGates
  # Boolean flags with environment > configuration > runtime > false precedence.
  # Runtime state uses Feature's lifecycle and is local to this process unless
  # a shared store is configured.
  class Flags
    attr_accessor :configuration
    attr_reader :store

    def initialize(env: ENV, configuration: {}, store: nil, prefix: 'star_gates:flags')
      @env = env
      @configuration = configuration
      @store = store
      @prefix = prefix
      @runtime = {}
      @mutex = Mutex.new
    end

    def store=(store)
      @mutex.synchronize do
        @runtime.clear
        @store = store
      end
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
      normalized = normalize(name)
      if @store
        store_remove(normalized) if normalized
      else
        @mutex.synchronize { @runtime.delete(normalized) }
      end
      nil
    end

    def reset!
      @store ? store_reset : @mutex.synchronize { @runtime.clear }
      nil
    end

    def all
      configured = configuration_flags
      runtime = runtime_values
      names = (environment_flags.keys + configured.keys + runtime.keys).uniq
      names.to_h { |name| [name, resolution(name, configured, runtime[name]).slice(:enabled, :source)] }
    end

    def enabled_flags
      all.select { |_, flag| flag[:enabled] }.keys.map(&:to_sym)
    end

    def summary
      {
        runtime_flags: runtime_values.keys.map(&:to_sym),
        environment_flags: environment_flags.keys.map(&:to_sym),
        configuration_flags: configuration_flags.keys.map(&:to_sym),
        all_enabled: enabled_flags
      }
    end

    def debug(name)
      normalized = normalize(name)
      resolution(normalized, configuration_flags, runtime_value(normalized))
    end

    def flag_status(name)
      normalized = normalize(name)
      details = debug(normalized)
      { name: normalized&.to_sym, enabled: details[:enabled], source: details[:source],
        metadata: runtime_metadata(normalized) }
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
      return store_update(normalized, enabled, metadata) if @store

      @mutex.synchronize do
        entry = @runtime[normalized] ||= { feature: Feature.new, metadata: {} }
        feature = entry.fetch(:feature)
        feature.enable if enabled && feature.disabled?
        feature.disable if !enabled && !feature.disabled?
        entry[:metadata] = metadata.dup if metadata
      end
      enabled
    end

    def runtime_value(name)
      return unless name
      return store_values([name])[name] if @store

      @mutex.synchronize { @runtime[name]&.fetch(:feature)&.enabled_for? }
    end

    def runtime_values
      return store_values(store_names) if @store

      @mutex.synchronize { @runtime.transform_values { |entry| entry.fetch(:feature).enabled_for? } }
    end

    def runtime_metadata(name)
      return {} unless name

      metadata = if @store
                   @store.read(metadata_key(name))
                 else
                   @mutex.synchronize { @runtime[name]&.fetch(:metadata) }
                 end
      metadata.is_a?(Hash) ? metadata.dup : {}
    end

    def store_update(name, enabled, metadata)
      index_add(name)
      store_write(flag_key(name), enabled)
      store_write(metadata_key(name), metadata.dup) if metadata
      enabled
    end

    def store_remove(name)
      store_delete([flag_key(name), metadata_key(name)])
    end

    def store_reset
      slots = index_slot_keys
      names = slots ? store_read(slots).values.uniq : legacy_index
      keys = names.flat_map { |name| [flag_key(name), metadata_key(name)] }
      store_delete(keys + (slots ? slots + [index_sequence_key] : [index_key]))
    end

    def index_add(name)
      return unless @store.read(flag_key(name)).nil?
      return @mutex.synchronize { legacy_index_add(name) } unless @store.respond_to?(:increment)

      slot = @store.increment(index_sequence_key)
      store_write(index_slot_key(slot), name) if slot
    end

    def store_names
      slots = index_slot_keys
      slots ? store_read(slots).values.uniq : legacy_index
    end

    def index_slot_keys
      return unless @store.respond_to?(:increment)

      Array.new(@store.read(index_sequence_key, raw: true).to_i) { |slot| index_slot_key(slot + 1) }
    end

    def legacy_index_add(name)
      names = legacy_index
      store_write(index_key, names + [name]) unless names.include?(name)
    end

    def legacy_index
      names = @store.read(index_key)
      names.is_a?(Array) ? names : []
    end

    def store_values(names)
      keys = names.to_h { |name| [flag_key(name), name] }
      store_read(keys.keys).each_with_object({}) do |(key, value), values|
        values[keys.fetch(key)] = value if [true, false].include?(value)
      end
    end

    def store_read(keys)
      return {} if keys.empty?
      return @store.read_multi(*keys) if @store.respond_to?(:read_multi)

      keys.each_with_object({}) do |key, values|
        value = @store.read(key)
        values[key] = value unless value.nil?
      end
    end

    def store_write(key, value)
      return if @store.write(key, value)

      raise Error, "#{@store.class} did not persist #{key}"
    end

    def store_delete(keys)
      return @store.delete_multi(keys) if @store.respond_to?(:delete_multi)

      keys.each { |key| @store.delete(key) }
    end

    def flag_key(name)
      "#{@prefix}:flag:#{name}"
    end

    def metadata_key(name)
      "#{@prefix}:metadata:#{name}"
    end

    def index_key
      "#{@prefix}:names"
    end

    def index_sequence_key
      "#{@prefix}:name_sequence"
    end

    def index_slot_key(slot)
      "#{@prefix}:name:#{slot}"
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

    def resolution(name, configured, runtime_value)
      env_key = "FEATURE_#{name&.upcase}"
      environment_value = name && @env[env_key]

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
