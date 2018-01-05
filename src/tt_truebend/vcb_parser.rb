require 'tt_truebend/validator'

module TT::Plugins::TrueBend
  class VCBParser

    def initialize(text)
      @text = text
    end

    def degrees?
      @text.end_with?('deg')
    end

    def degrees
      Validator.new(@text.to_f.degrees)
    end

    def length
      Validator.new(@text.to_l)
    end

    def modifier?
      !!@text.match(/[^0-9]+$/)
    end

    def numeric?
      !!@text.match(/^[0-9.,]+$/)
    end

    def segments?
      @text.end_with?('s')
    end

    def segments
      Validator.new(@text.to_i)
    end

  end
end # module
