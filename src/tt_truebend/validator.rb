module TT::Plugins::TrueBend
  # Interface for validating user input and applying constraints to it.
  class Validator

    # Raised when the input value doesn't fall within the constraints applied.
    class ValidationError < ArgumentError; end

    attr_reader :value

    # @param [Numeric] value
    def initialize(value)
      @value = value
    end

    # @param [Numeric] max
    def max(max)
      raise ValidationError, "Value must be no more than #{max}" if @value > max

      self
    end

    # @param [Numeric] min
    def min(min)
      raise ValidationError, "Value must be no less than #{min}" if @value < min

      self
    end

  end
end # module
