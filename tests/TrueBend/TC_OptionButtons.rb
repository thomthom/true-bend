#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'

require 'tt_truebend/gl/option_buttons'

module TT::Plugins::TrueBend
  module Tests
    class TC_OptionButtons < TestUp::TestCase

      def setup
        # ...
      end

      def teardown
        # ...
      end


      def test_pick_the_middle_of_each_button
        buttons = OptionButtons.new

        OptionButtons::OPTIONS.each { |option|
          assert_equal(option, buttons.pick(*buttons.center(option)))
        }
      end

      def test_pick_between_and_around_the_buttons
        buttons = OptionButtons.new
        x, y = buttons.center(:angle)
        between = (x + buttons.center(:distance)[0]) / 2
        between_groups = (buttons.center(:radius)[0] + buttons.center(:segmented)[0]) / 2

        assert_nil(buttons.pick(between, y), 'Between two buttons')
        assert_nil(buttons.pick(between_groups, y), 'Between the two groups')
        assert_nil(buttons.pick(x - OptionButtons::SIZE, y), 'Left of the buttons')
        assert_nil(buttons.pick(x, y - OptionButtons::SIZE), 'Above the buttons')
        assert_nil(buttons.pick(x, y + OptionButtons::SIZE), 'Below the buttons')
        right = buttons.center(:soft_smooth)[0] + OptionButtons::SIZE
        assert_nil(buttons.pick(right, y), 'Right of the buttons')
      end

      def test_pick_leaves_the_axis_buttons_on_the_same_row_alone
        buttons = OptionButtons.new
        axis_buttons = AxisButtons.new

        3.times { |axis|
          assert_nil(buttons.pick(*axis_buttons.center(axis)))
        }
        OptionButtons::OPTIONS.each { |option|
          assert_nil(axis_buttons.pick(*buttons.center(option)))
        }
      end

      def test_center_sets_the_groups_apart_on_the_row_of_the_axis_buttons
        buttons = OptionButtons.new
        axis_buttons = AxisButtons.new
        step = OptionButtons::SIZE + OptionButtons::SPACING
        group_step = OptionButtons::SIZE + OptionButtons::GROUP_SPACING
        x, y = axis_buttons.center(2)

        assert_equal([x + group_step, y], buttons.center(:angle))
        assert_equal([x + group_step + step, y], buttons.center(:distance))
        x = buttons.center(:radius)[0]
        assert_equal([x + group_step, y], buttons.center(:segmented))
        assert_equal([x + group_step + step, y], buttons.center(:soft_smooth))
      end

      def test_glyph_for_every_option_stays_inside_its_button
        OptionButtons::OPTIONS.each { |option|
          lines = OptionButtons::GLYPHS.fetch(option)
          points = lines.flat_map { |_stipple, line| line }
          refute_empty(points, option.to_s)
          points.flatten.each { |coordinate|
            assert_operator(coordinate, :>, 0, option.to_s)
            assert_operator(coordinate, :<, OptionButtons::SIZE, option.to_s)
          }
        }
      end

    end # class
  end # module
end # module
