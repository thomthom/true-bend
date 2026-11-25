#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'

require 'tt_truebend/validator'
require 'tt_truebend/vcb_parser'

module TT::Plugins::TrueBend
  module Tests
    # The lengths in these tests carry a unit and no decimals, so they read the
    # same whichever units and decimal separator the model and system use.
    class TC_VCBParser < TestUp::TestCase

      def setup
        # ...
      end

      def teardown
        # ...
      end


      def test_degrees_query
        assert(VCBParser.new('45deg').degrees?)
        refute(VCBParser.new('45').degrees?)
        refute(VCBParser.new('45s').degrees?)
        refute(VCBParser.new('45mm').degrees?)
        refute(VCBParser.new('45r').degrees?)
      end

      def test_degrees
        result = VCBParser.new('45deg').degrees

        assert_kind_of(Validator, result)
        assert_in_delta(Math::PI / 4.0, result.value, 1.0e-9)
      end

      def test_degrees_without_modifier
        assert_in_delta(Math::PI / 2.0, VCBParser.new('90').degrees.value, 1.0e-9)
      end

      def test_length
        result = VCBParser.new('254mm').length

        assert_kind_of(Validator, result)
        assert_kind_of(Length, result.value)
        assert_in_delta(10.0, result.value.to_f, 1.0e-9)
      end

      def test_length_negative
        assert_in_delta(-10.0, VCBParser.new('-10"').length.value.to_f, 1.0e-9)
      end

      def test_length_invalid
        parser = VCBParser.new('nonsense')

        assert_raises(VCBParser::InputError) { parser.length }
      end

      def test_modifier_query
        assert(VCBParser.new('45deg').modifier?)
        assert(VCBParser.new('12s').modifier?)
        assert(VCBParser.new('10mm').modifier?)
        assert(VCBParser.new('10mmr').modifier?)
        refute(VCBParser.new('10').modifier?)
        refute(VCBParser.new('-10').modifier?)
      end

      def test_numeric_query
        assert(VCBParser.new('10').numeric?)
        assert(VCBParser.new('10.5').numeric?)
        assert(VCBParser.new('10,5').numeric?)
        refute(VCBParser.new('10s').numeric?)
        refute(VCBParser.new('10deg').numeric?)
        refute(VCBParser.new('').numeric?)
      end

      def test_radius_query
        assert(VCBParser.new('254mmr').radius?)
        assert(VCBParser.new('10r').radius?)
        refute(VCBParser.new('10').radius?)
        refute(VCBParser.new('10mm').radius?)
        refute(VCBParser.new('10deg').radius?)
        refute(VCBParser.new('10s').radius?)
      end

      def test_radius
        result = VCBParser.new('254mmr').radius

        assert_kind_of(Validator, result)
        assert_kind_of(Length, result.value)
        assert_in_delta(10.0, result.value.to_f, 1.0e-9)
      end

      def test_radius_with_whitespace_before_the_radius_notation
        assert_in_delta(10.0, VCBParser.new('254mm r').radius.value.to_f, 1.0e-9)
      end

      def test_radius_without_the_radius_notation
        assert_in_delta(10.0, VCBParser.new('254mm').radius.value.to_f, 1.0e-9)
      end

      def test_radius_negative
        assert_in_delta(-10.0, VCBParser.new('-10"r').radius.value.to_f, 1.0e-9)
      end

      def test_radius_invalid
        parser = VCBParser.new('nonsenser')

        assert_raises(VCBParser::InputError) { parser.radius }
      end

      def test_segments_query
        assert(VCBParser.new('12s').segments?)
        refute(VCBParser.new('12').segments?)
        refute(VCBParser.new('12deg').segments?)
        refute(VCBParser.new('12r').segments?)
      end

      def test_segments
        result = VCBParser.new('12s').segments

        assert_kind_of(Validator, result)
        assert_equal(12, result.value)
      end

      def test_validator_min
        validator = Validator.new(5)

        assert_same(validator, validator.min(5))
        assert_raises(Validator::ValidationError) { validator.min(6) }
      end

      def test_validator_max
        validator = Validator.new(5)

        assert_same(validator, validator.max(5))
        assert_raises(Validator::ValidationError) { validator.max(4) }
      end

    end # class
  end # module
end # module
