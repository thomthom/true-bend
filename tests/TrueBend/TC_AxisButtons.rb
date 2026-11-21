#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'

require 'tt_truebend/gl/axis_buttons'

module TT::Plugins::TrueBend
  module Tests
    class TC_AxisButtons < TestUp::TestCase

      def setup
        # ...
      end

      def teardown
        # ...
      end


      def test_pick_the_middle_of_each_button
        buttons = AxisButtons.new

        3.times { |axis|
          assert_equal(axis, buttons.pick(*buttons.center(axis)))
        }
      end

      def test_pick_between_and_around_the_buttons
        buttons = AxisButtons.new
        x, y = buttons.center(0)
        between = (x + buttons.center(1)[0]) / 2

        assert_nil(buttons.pick(between, y), 'Between two buttons')
        assert_nil(buttons.pick(x - AxisButtons::SIZE, y), 'Left of the buttons')
        assert_nil(buttons.pick(x, y - AxisButtons::SIZE), 'Above the buttons')
        assert_nil(buttons.pick(x, y + AxisButtons::SIZE), 'Below the buttons')
        right = buttons.center(2)[0] + AxisButtons::SIZE
        assert_nil(buttons.pick(right, y), 'Right of the buttons')
      end

    end # class
  end # module
end # module
