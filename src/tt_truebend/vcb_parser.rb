require 'tt_truebend/validator'

module TT::Plugins::TrueBend
  # Parses the given input string. For the various types of values parsed
  # a {Validator} object is returned that is in turn used to enforce constraints
  # to the input value.
  class VCBParser

    # Raised when the input cannot be parsed.
    class InputError < ArgumentError; end

    # @param [String] text
    def initialize(text)
      @text = text
    end

    # Checks if the input is degrees notation.
    def degrees?
      @text.end_with?('deg')
    end

    # @return [Validator]
    def degrees
      Validator.new(@text.to_f.degrees)
    end

    # @return [Validator]
    #
    # @raise [InputError]
    def length
      Validator.new(@text.to_l)
    rescue ArgumentError => error
      raise InputError, error.message
    end

    # Check if the input have a modifier postfix.
    def modifier?
      !!@text.match(/[^0-9]+$/)
    end

    # Is the input numeric only.
    def numeric?
      !!@text.match(/^[0-9.,]+$/)
    end

    # Checks if the input is radius notation, like the native arc tools use.
    def radius?
      @text.end_with?('r')
    end

    # Accepts the length with or without the "r" suffix.
    #
    # @return [Validator]
    #
    # @raise [InputError]
    def radius
      length_without('r')
    end

    def sagitta?
      @text.end_with?('sg')
    end

    # Accepts the length with or without the "sg" suffix.
    #
    # @return [Validator]
    #
    # @raise [InputError]
    def sagitta
      length_without('sg')
    end

    # Checks if the input is segments notation.
    def segments?
      @text.end_with?('s')
    end

    # @return [Validator]
    def segments
      Validator.new(@text.to_i)
    end

    private

    # @param [String] suffix The notation that might follow the length.
    # @return [Validator]
    #
    # @raise [InputError]
    def length_without(suffix)
      # `String#to_l` rejects trailing whitespace after a unit.
      Validator.new(@text.chomp(suffix).rstrip.to_l)
    rescue ArgumentError => error
      raise InputError, error.message
    end

  end
end # module
