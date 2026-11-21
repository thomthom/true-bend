#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'
require_relative '../lib/test_utilities'

require 'tt_truebend/main'

module TT::Plugins::TrueBend
  module Tests
    # The command that starts the bend tool, from the menu or the toolbar.
    class TC_Main < TestUp::TestCase

      include TrueBendTestUtilities

      X = BendAxes::X
      Y = BendAxes::Y
      Z = BendAxes::Z

      SELECT_ONE_INSTANCE = 'Select a single Group or Component to bend.'.freeze
      NO_LENGTH = 'Unable to bend because the instance has no length along any of its axes.'.freeze

      def setup
        start_with_empty_model
        @messages = []
      end

      def teardown
        # Puts away the tool that a test started.
        Sketchup.active_model.select_tool(nil)
      end


      # Runs the command with the given entities selected. The message boxes
      # it shows are collected instead, and an error fails the test instead of
      # opening the error dialog.
      #
      # @param [Array<Sketchup::Entity>] entities
      def activate_true_bend(*entities)
        selection = Sketchup.active_model.selection
        selection.clear
        selection.add(entities) unless entities.empty?
        raise_error = ->(error) { raise error }
        collect_message = lambda { |message, *_options|
          @messages << message
          IDOK
        }
        ERROR_REPORTER.stub(:handle, raise_error) {
          UI.stub(:messagebox, collect_message) {
            TT::Plugins::TrueBend.activate_true_bend
          }
        }
      end

      # @return [String] The name SketchUp gives the tool that is active.
      def active_tool_name
        Sketchup.active_model.tools.active_tool_name
      end


      def test_activate_true_bend_starts_the_tool_for_a_group
        instance = create_solid(X)
        tool_name = active_tool_name

        activate_true_bend(instance)

        assert_empty(@messages)
        refute_equal(tool_name, active_tool_name)
        assert_equal('RubyTool', active_tool_name)
      end

      def test_activate_true_bend_starts_the_tool_for_a_component
        instance = create_solid(X).to_component

        activate_true_bend(instance)

        assert_empty(@messages)
        assert_equal('RubyTool', active_tool_name)
      end

      def test_activate_true_bend_without_a_selection_asks_for_one
        create_solid(X)
        tool_name = active_tool_name

        activate_true_bend

        assert_equal([SELECT_ONE_INSTANCE], @messages)
        assert_equal(tool_name, active_tool_name)
      end

      def test_activate_true_bend_with_two_instances_asks_for_one
        instances = [create_solid(X), create_solid(X)]
        tool_name = active_tool_name

        activate_true_bend(*instances)

        assert_equal([SELECT_ONE_INSTANCE], @messages)
        assert_equal(tool_name, active_tool_name)
      end

      def test_activate_true_bend_with_only_an_edge_asks_for_an_instance
        edge = Sketchup.active_model.entities.add_line(ORIGIN, Geom::Point3d.new(10, 0, 0))
        tool_name = active_tool_name

        activate_true_bend(edge)

        assert_equal([SELECT_ONE_INSTANCE], @messages)
        assert_equal(tool_name, active_tool_name)
      end

      def test_activate_true_bend_starts_the_tool_without_length_along_red
        instance = create_flat_instance(X)

        activate_true_bend(instance)

        assert_empty(@messages)
        assert_equal('RubyTool', active_tool_name)
      end

      def test_activate_true_bend_tells_when_the_instance_has_no_length
        instance = Sketchup.active_model.entities.add_group
        instance.entities.add_cpoint(Geom::Point3d.new(1, 2, 3))
        tool_name = active_tool_name

        activate_true_bend(instance)

        assert_equal([NO_LENGTH], @messages)
        assert_equal(tool_name, active_tool_name)
      end

    end # class
  end # module
end # module
