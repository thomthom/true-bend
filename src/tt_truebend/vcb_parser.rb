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

    # Checks if the input is segments notation.
    def segments?
      @text.end_with?('s')
    end

    # @return [Validator]
    def segments
      Validator.new(@text.to_i)
    end

  end
end # module
