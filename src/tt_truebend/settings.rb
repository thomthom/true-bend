module TT::Plugins::TrueBend
  class Settings

    # A setting with a Symbol as its default is read back as a Symbol. This
    # only applies when the whole value is a Symbol, not to symbols inside an
    # Array.
    #
    # @param [Symbol] key
    # @param [Object] default
    def self.define(key, default = nil)
      read_method = boolean?(default) ? "#{key}?".to_sym : key.to_sym
      write_method = "#{key}=".to_sym
      self.class_eval {
        define_method(read_method) {
          value = read(key.to_s, default)
          default.is_a?(Symbol) ? symbol_value(value, default) : value
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

    # @param [Object] value
    # @param [Object] default
    # @return [Object] The default if the value is neither a String nor a
    #   Symbol.
    def symbol_value(value, default)
      case value
      when Symbol then value
      when String then value.to_sym
      else default
      end
    end

    def write(key, value)
      @cache[key] = value
      # SketchUp reads a Symbol back as nil, so it is stored as a String.
      stored_value = value.is_a?(Symbol) ? value.to_s : value
      Sketchup.write_default(@preference_id, key, escape_strings(stored_value))
      value
    end

    # SketchUp evaluates a stored String as a double-quoted Ruby String literal
    # when it reads a preference. Unescaped, a double quote makes the
    # preference read back as nil, a backslash starts an escape sequence and
    # "#{}" is interpolated.
    #
    # @param [Object] value
    # @return [Object]
    def escape_strings(value)
      # TODO(thomthom): Include Hash? Likely value to store.
      case value
      when String
        value.gsub(/[\\"#]/) { |character| "\\#{character}" }
      when Array
        value.map { |sub_value| escape_strings(sub_value) }
      else
        value
      end
    end

  end # class
end # module
