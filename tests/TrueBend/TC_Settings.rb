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
        define :items, []

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

      # Runs the block with an in-memory hash in place of the SketchUp
      # preferences. Unlike `with_preferences`, it stores and reads values the
      # way SketchUp 2017 and 2027 were observed to. A String is stored between
      # double quotes without any escaping, and the stored text is evaluated as
      # Ruby code when it is read. Text that fails to evaluate is read as nil.
      def with_evaluated_preferences(&block)
        stored = {}
        read = lambda { |_section, key, default = nil|
          stored.key?(key) ? evaluate_preference(stored[key]) : default
        }
        write = lambda { |_section, key, value|
          stored[key] = preference_text(value)
          true
        }
        Sketchup.stub(:read_default, read) {
          Sketchup.stub(:write_default, write, &block)
        }
      end

      # @param [Object] value
      # @return [String]
      def preference_text(value)
        case value
        when String then %("#{value}")
        when Array then "[#{value.map { |item| preference_text(item) }.join(', ')}]"
        else value.inspect
        end
      end

      # @param [String] text
      # @return [Object]
      def evaluate_preference(text)
        eval(text) # rubocop:disable Security/Eval
      rescue SyntaxError, StandardError
        nil
      end

      # A new Settings instance has an empty cache, like the one a new SketchUp
      # session starts with.
      #
      # @param [Symbol] key
      # @param [Object] value
      # @return [Object] The value that a new session reads.
      def value_in_new_session(key, value)
        with_evaluated_preferences {
          ExampleSettings.new('Example').send("#{key}=", value)
          ExampleSettings.new('Example').send(key)
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

      def test_string_setting_with_a_quote_is_unchanged_in_a_new_session
        value = %q(1' 2 1/2")

        assert_equal(value, value_in_new_session(:label, value))
      end

      def test_string_setting_with_a_backslash_is_unchanged_in_a_new_session
        value = 'C:\Users\name\table'
        assert_equal(value, value_in_new_session(:label, value), 'path')

        value = 'folder\\'
        assert_equal(value, value_in_new_session(:label, value), 'at the end')

        value = 'a\"b'
        assert_equal(value, value_in_new_session(:label, value), 'before quote')
      end

      def test_string_setting_with_interpolation_syntax_is_not_evaluated
        value = ['a#', '{1 + 1}b'].join
        assert_equal(value, value_in_new_session(:label, value), 'expression')

        value = ['a#', '$PROGRAM_NAME'].join
        assert_equal(value, value_in_new_session(:label, value), 'global')

        value = 'a # b#'
        assert_equal(value, value_in_new_session(:label, value), 'plain hash')
      end

      def test_strings_in_an_array_setting_are_unchanged_in_a_new_session
        value = ['a"b', 'c\d', ['a#', '{1 + 1}b'].join, 5, ['e"f\\']]

        assert_equal(value, value_in_new_session(:items, value))
      end

      def test_boolean_setting_is_read_with_a_predicate
        with_preferences('enabled' => false) {
          refute(ExampleSettings.new('Example').enabled?)
        }
      end

      def test_reader_does_not_accept_a_default
        with_preferences {
          settings = ExampleSettings.new('Example')

          assert_raises(ArgumentError, 'reader') { settings.mode(:radius) }
          assert_raises(ArgumentError, 'predicate') { settings.enabled?(false) }
          assert_equal(:angle, settings.mode)
        }
      end

    end # class
  end # module
end # module
