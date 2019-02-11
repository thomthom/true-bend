module TT::Plugins::TrueBend
  class Validator

    class ValidationError < ArgumentError; end

    attr_reader :value

    def initialize(value)
      @value = value
    end

    def max(max)
      raise ValidationError, "Value must be no more than #{max}" if @value > max

      self
    end

    def min(min)
      raise ValidationError, "Value must be no less than #{min}" if @value < min

      self
    end

  end
end # module
