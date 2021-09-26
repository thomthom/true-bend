module TT::Plugins::TrueBend
  class Settings

    # @param [Symbol] key
    # @param [Object] default
    def self.define(key, default = nil)
      read_method = boolean?(default) ? "#{key}?".to_sym : key.to_sym
      write_method = "#{key}=".to_sym
      self.class_eval {
        define_method(read_method) { |default_value = default|
          read(key.to_s, default_value)
        }
        define_method(write_method) { |value|
          write(key.to_s, value)
        }
      }
    end

    # @param [Object] value
    def self.boolean?(value)
      value.is_a?(TrueClass) || value.is_a?(FalseClass)
    end

    # @param [String] preference_id
    def initialize(preference_id)
      @preference_id = preference_id
      # Reading and writing to the registry is slow. Cache values in order to
      # gain performance improvements.
      @cache = {}
    end

    # @return [String]
    def inspect
      to_s
    end

    private

    def read(key, default = nil)
      if @cache.key?(key)
        @cache[key]
      else
        value = Sketchup.read_default(@preference_id, key, default)
        @cache[key] = value
        value
      end
    end

    def write(key, value)
      @cache[key] = value
      escaped_value = escape_quotes(value)
      Sketchup.write_default(@preference_id, key, escaped_value)
      value
    end

    def escape_quotes(value)
      # TODO(thomthom): Include Hash? Likely value to store.
      case value
      when String
        value.gsub(/"/, '\\"')
      when Array
        value.map { |sub_value| escape_quotes(sub_value) }
      else
        value
      end
    end

  end
end # module TT::Plugins::SUbD
