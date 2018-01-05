module TT::Plugins::TrueBend
  class Validator

    attr_reader :value

    def initialize(value)
      @value = value
    end

    def max(max)
      raise ArgumentError if @value > max
      self
    end

    def min(min)
      raise ArgumentError if @value < min
      self
    end

  end
end # module
