#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'

require 'tt_truebend/settings'

module TT::Plugins::TrueBend
  module Tests
    class TC_Settings < TestUp::TestCase

      class ExampleSettings < Settings

        define :mode, :angle
        define :label, 'untitled'
        define :enabled, true

      end

      def setup
        # ...
      end

      def teardown
        # ...
      end


      # Runs the block with an in-memory hash in place of the SketchUp
      # preferences.
      #
      # @param [Hash{String => Object}] stored
      # @yieldparam [Hash{String => Object}] stored
      def with_preferences(stored = {}, &block)
        read = ->(_section, key, default = nil) { stored.fetch(key, default) }
        write = lambda { |_section, key, value|
          stored[key] = value
          true
        }
        Sketchup.stub(:read_default, read) {
          Sketchup.stub(:write_default, write) { block.call(stored) }
        }
      end

      def test_symbol_setting_defaults_to_its_symbol
        with_preferences {
          assert_equal(:angle, ExampleSettings.new('Example').mode)
        }
      end

      def test_symbol_setting_is_stored_as_a_string
        with_preferences { |stored|
          settings = ExampleSettings.new('Example')

          settings.mode = :radius

          assert_equal('radius', stored['mode'])
          assert_equal(:radius, settings.mode)
        }
      end

      def test_symbol_setting_is_read_back_as_a_symbol
        with_preferences('mode' => 'radius') {
          assert_equal(:radius, ExampleSettings.new('Example').mode)
        }
      end

      def test_symbol_setting_falls_back_to_its_default_for_another_type
        with_preferences('mode' => nil) {
          assert_equal(:angle, ExampleSettings.new('Example').mode, 'nil')
        }
        with_preferences('mode' => 5) {
          assert_equal(:angle, ExampleSettings.new('Example').mode, 'Integer')
        }
      end

      def test_string_setting_is_read_back_as_a_string
        with_preferences('label' => 'radius') {
          assert_equal('radius', ExampleSettings.new('Example').label)
        }
      end

      def test_boolean_setting_is_read_with_a_predicate
        with_preferences('enabled' => false) {
          refute(ExampleSettings.new('Example').enabled?)
        }
      end

    end # class
  end # module
end # module
