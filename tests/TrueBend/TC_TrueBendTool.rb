#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'
require_relative '../lib/test_utilities'

require 'tt_truebend/dpi/view'
require 'tt_truebend/tools/truebend'

module TT::Plugins::TrueBend
  module Tests
    class TC_TrueBendTool < TestUp::TestCase

      include TrueBendTestUtilities

      X = BendAxes::X
      Y = BendAxes::Y
      Z = BendAxes::Z

      ROTATION = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 2, 3), 37.degrees)
      TRANSLATION = Geom::Transformation.translation(Geom::Vector3d.new(30, -40, 50))

      # The test solid is 100" long. Dragging the bend handle this far bends it
      # a quarter of a circle.
      QUARTER_CIRCLE_DRAG = 100.0 / Math::PI / 4.0

      def setup
        start_with_empty_model
        @beeps = 0
        @messages = []
      end

      def teardown
        # ...
      end


      # Runs the block without the ways the tool reaches out to the user.
      #
      # The tool reports its errors in a modal dialog, which would leave the
      # test run waiting for someone to close it, so they fail the test instead.
      # It beeps when it refuses input, and shows a message box for input it
      # doesn't understand, so those are collected instead.
      def without_user_feedback(&block)
        raise_error = ->(error) { raise error }
        count_beep = -> { @beeps += 1 }
        collect_message = lambda { |message, *_options|
          @messages << message
          IDOK
        }
        ERROR_REPORTER.stub(:handle, raise_error) {
          UI.stub(:beep, count_beep) {
            UI.stub(:messagebox, collect_message, &block)
          }
        }
      end

      # @param [TrueBendTool] tool
      # @param [Integer] key
      # @return [Boolean] Whether the tool handled the key.
      def press(tool, key)
        without_user_feedback {
          tool.onKeyDown(key, 1, 0, Sketchup.active_model.active_view)
        }
      end

      # @param [TrueBendTool] tool
      # @return [BendAxes] The way the tool is set up to bend the instance.
      def axes_of(tool)
        tool.instance_variable_get(:@axes)
      end

      # @param [TrueBendTool] tool
      # @return [Bender]
      def bender_of(tool)
        tool.instance_variable_get(:@bender)
      end

      # Asserts that the tool is set up to bend the instance along the given
      # axis, towards the given one of the two faces on offer for that axis.
      #
      # @param [TrueBendTool] tool
      # @param [Sketchup::Group] instance
      # @param [Integer] axis
      # @param [Integer] face_index
      def assert_bend(tool, instance, axis, face_index, message = nil)
        expected = BendAxes.along(instance, axis)[face_index]
        axes = axes_of(tool)
        assert_equal(AXIS_NAMES[axis], AXIS_NAMES[axes.axis], message)
        assert_vector(expected.normal, axes.normal, message)
        # The bend itself has to be set up the same way.
        bender = bender_of(tool)
        assert_point(expected.segment.start, bender.segment.start, message)
        assert_point(expected.segment.end, bender.segment.end, message)
        bender.distance = 1
        assert_vector(expected.normal, bender.direction, message)
        bender.reset
      end

      # @param [TrueBendTool] tool
      # @return [DragHandle] The handle for the direction the tool is set up to
      #   bend in.
      def handle_of(tool)
        tool.instance_variable_get(:@manipulator)
      end

      # @param [TrueBendTool] tool
      # @return [Array<DragHandle>] The handles for the directions the instance
      #   can be bent in, in the order `BendAxes.along` gives the directions.
      def handles_of(tool)
        tool.instance_variable_get(:@handles).values
      end

      # @param [TrueBendTool] tool
      # @param [Sketchup::Model] model
      # @return [Boolean] Whether the tool is told when the model changes.
      def watches?(tool, model)
        observer = tool.instance_variable_get(:@observer)
        watching = model.remove_observer(observer)
        model.add_observer(observer) if watching
        watching
      end

      # Looks at the instance from in front, to the right and above, so that
      # no edges of its bounds are behind one another.
      #
      # @param [Sketchup::Group] instance
      def look_at(instance)
        target = instance.bounds.center
        eye = target.offset(Geom::Vector3d.new(150, -200, 120))
        camera = Sketchup::Camera.new(eye, target, Z_AXIS)
        Sketchup.active_model.active_view.camera = camera
      end

      # Looks at a bend handle of the test solid from close by and from the
      # side, so that a drag along the handle covers many pixels.
      #
      # @param [TrueBendTool] tool
      # @param [DragHandle] handle
      def look_at_handle(tool, handle = handle_of(tool))
        target = handle.origin
        # Two directions across the handle.
        across, upwards = handle.normal.axes
        eye = target.offset(across, 40).offset(upwards, 20)
        camera = Sketchup::Camera.new(eye, target, Z_AXIS)
        Sketchup.active_model.active_view.camera = camera
      end

      # How far off the angle of a bend can be after dragging the handle.
      #
      # A position in the viewport is a whole pixel, so each end of a drag can
      # be half a pixel off. Twice that is allowed for.
      #
      # @param [TrueBendTool] tool
      # @param [Integer] drags How many drags the bend was made with.
      # @return [Float] In radians.
      def drag_tolerance(tool, drags = 1)
        view = Sketchup.active_model.active_view
        pixel = view.pixels_to_model(1, handle_of(tool).origin).to_f
        full_circle_drag = bender_of(tool).max_bend_distance.to_f
        360.degrees * (2.0 * drags * pixel / full_circle_drag)
      end

      # @param [Geom::Point3d] point
      # @return [Array(Float, Float)] Where the point is in the viewport, in
      #   device pixels, as SketchUp gives positions to a tool.
      def screen_position(point)
        screen_point = Sketchup.active_model.active_view.screen_coords(point)
        [screen_point.x, screen_point.y]
      end

      # Presses the left mouse button at one position in the viewport, and
      # lets it go at another.
      #
      # @param [TrueBendTool] tool
      # @param [Array(Numeric, Numeric)] start In device pixels.
      # @param [Array(Numeric, Numeric)] finish In device pixels.
      def drag(tool, start, finish)
        view = Sketchup.active_model.active_view
        without_user_feedback {
          tool.onMouseMove(0, *start, view)
          tool.onLButtonDown(0, *start, view)
          tool.onMouseMove(0, *finish, view)
          tool.onLButtonUp(0, *finish, view)
        }
      end

      # Clicks the left mouse button in the viewport.
      #
      # @param [TrueBendTool] tool
      # @param [Array(Numeric, Numeric)] position In device pixels, as SketchUp
      #   gives positions to a tool.
      # @param [Array(Numeric, Numeric)] release_position Where the mouse
      #   button is let go, when that is somewhere else.
      def click(tool, position, release_position = position)
        drag(tool, position, release_position)
      end

      # The edges of the bounds that are picked in the tests, as the corners
      # they run between, for each axis. They are the ones around the left end
      # of the top of the bounds, which keep clear of the bend handles.
      BOUNDS_EDGES = [[4, 5], [4, 6], [0, 4]].freeze

      # @param [Sketchup::Group] instance
      # @param [Integer] axis The axis the edge runs along.
      # @return [Array(Numeric, Numeric)] A point on an edge of the bounds of
      #   the instance, in device pixels.
      def edge_position(instance, axis)
        bounds = instance.definition.bounds
        corners = BOUNDS_EDGES[axis].map { |index|
          bounds.corner(index).transform(instance.transformation)
        }
        point = Geom.linear_combination(0.75, corners[0], 0.25, corners[1])
        screen_position(point)
      end

      # Drags a bend handle, from the middle of it.
      #
      # @param [TrueBendTool] tool
      # @param [Float] distance How far to drag it away from the instance.
      #   Negative to drag it into the instance.
      # @param [DragHandle] handle
      def drag_handle(tool, distance, handle = handle_of(tool))
        view = HighDpiView.new(Sketchup.active_model.active_view)
        half_length = view.pixels_to_model(handle.size / 2, handle.origin)
        middle = handle.origin.offset(handle.normal, half_length)
        target = middle.offset(handle.normal, distance)
        drag(tool, screen_position(middle), screen_position(target))
      end

      # @return [Array(Float, Float)] A position in the viewport that is clear
      #   of the bend handle, in device pixels.
      def empty_position
        view = Sketchup.active_model.active_view
        [view.vpwidth - 5, view.vpheight - 5]
      end

      # Types into the Measurements box.
      #
      # @param [TrueBendTool] tool
      # @param [String] text
      def type(tool, text)
        without_user_feedback {
          tool.onUserText(text, Sketchup.active_model.active_view)
        }
      end

      # Asserts that the instance has been bent a quarter of a circle towards
      # its front, as a true circular bend.
      #
      # @param [Sketchup::Group] instance
      # @param [TrueBendTool] tool The tool that bent it.
      def assert_bent_quarter_circle(instance, tool)
        bender = bender_of(tool)
        expected = true_bend(sliced_solid_points(X, bender.subdivisions), bender.segment.points,
                             Y_AXIS.reverse, 90.degrees)
        assert_same_points(expected, world_positions(instance))
      end


      def test_initialize_bends_along_red_towards_the_front
        instance = create_solid(X)

        tool = TrueBendTool.new(instance)

        assert_bend(tool, instance, X, 0)
      end

      def test_initialize_bends_along_the_red_axis_through_the_origin
        instance = create_solid(X)

        tool = TrueBendTool.new(instance)

        segment = bender_of(tool).segment
        assert_point(Geom::Point3d.new(SOLID_START, 0, 0), segment.start)
        assert_point(Geom::Point3d.new(SOLID_END, 0, 0), segment.end)
      end

      def test_initialize_bends_towards_the_front
        instance = create_solid(X)

        tool = TrueBendTool.new(instance)

        bender = bender_of(tool)
        refute(bender.bending?)
        bender.distance = 1
        assert_vector(Geom::Vector3d.new(0, -1, 0), bender.direction)
        assert(bender.concave?)
      end

      def test_initialize_follows_how_the_instance_is_placed
        placement = TRANSLATION * ROTATION
        instance = create_solid(X, placement)

        tool = TrueBendTool.new(instance)

        bender = bender_of(tool)
        segment = bender.segment
        assert_point(Geom::Point3d.new(SOLID_START, 0, 0).transform(placement), segment.start)
        assert_point(Geom::Point3d.new(SOLID_END, 0, 0).transform(placement), segment.end)
        bender.distance = 1
        assert_vector(Geom::Vector3d.new(0, -1, 0).transform(placement), bender.direction)
      end

      def test_initialize_puts_the_handle_in_the_middle_of_the_front
        instance = create_solid(X)

        tool = TrueBendTool.new(instance)

        handle = handle_of(tool)
        # The front of the bounding box of the test solid.
        middle = Geom::Point3d.new((SOLID_START + SOLID_END) / 2.0,
                                   SOLID_START_SECTION[0][0],
                                   (SOLID_START_SECTION[0][1] + SOLID_START_SECTION[1][1]) / 2.0)
        assert_point(middle, handle.origin)
        assert_vector(Geom::Vector3d.new(0, -1, 0), handle.normal.normalize)
      end

      def test_initialize_has_a_handle_for_each_direction_to_bend_in
        instance = create_solid(X)

        tool = TrueBendTool.new(instance)

        handles = handles_of(tool)
        directions = BendAxes.along(instance, X)
        assert_equal(2, handles.size)
        %w[Front Top].each_with_index { |face, index|
          assert_point(directions[index].face_center, handles[index].origin, face)
          assert_vector(directions[index].normal, handles[index].normal, face)
        }
        assert_same(handles.first, handle_of(tool), 'The front handle is the one in use')
        assert_equal(TrueBendTool::ACTIVE_HANDLE_COLOR, handles.first.color)
        assert_equal(TrueBendTool::INACTIVE_HANDLE_COLOR, handles.last.color)
      end

      def test_initialize_flat_instance_bends_towards_the_front
        [Y, Z].each { |axis|
          instance = create_flat_instance(axis)

          tool = TrueBendTool.new(instance)

          bender = bender_of(tool)
          bender.distance = 1
          assert_vector(Geom::Vector3d.new(0, -1, 0), bender.direction,
                        "Flat across the #{%w[red green blue][axis]} axis")
        }
      end

      def test_initialize_falls_back_to_green_without_length_along_red
        instance = create_flat_instance(X)

        tool = TrueBendTool.new(instance)

        assert_bend(tool, instance, Y, 0)
      end

      def test_initialize_falls_back_to_blue_without_length_along_red_and_green
        instance = create_line_instance(Z)

        tool = TrueBendTool.new(instance)

        assert_bend(tool, instance, Z, 0)
      end

      def test_initialize_refuses_an_instance_without_length
        group = Sketchup.active_model.entities.add_group
        group.entities.add_cpoint(Geom::Point3d.new(1, 2, 3))

        assert_raises(TrueBendTool::BendError) {
          TrueBendTool.new(group)
        }
      end


      def test_on_key_down_arrow_keys_select_the_axis
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        assert(press(tool, VK_LEFT), 'Left arrow handled')
        assert_bend(tool, instance, Y, 0, 'Left arrow')

        assert(press(tool, VK_UP), 'Up arrow handled')
        assert_bend(tool, instance, Z, 0, 'Up arrow')

        assert(press(tool, VK_RIGHT), 'Right arrow handled')
        assert_bend(tool, instance, X, 0, 'Right arrow')

        assert_equal(0, @beeps)
      end

      def test_on_key_down_repeated_key_switches_the_bend_direction
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        keys = { VK_RIGHT => X, VK_LEFT => Y, VK_UP => Z }

        keys.each { |key, axis|
          name = AXIS_NAMES[axis]
          press(tool, key) unless axis == X # The tool starts out on red.
          assert_bend(tool, instance, axis, 0, "Selecting #{name}")

          assert(press(tool, key), "Repeated key for #{name} handled")
          assert_bend(tool, instance, axis, 1, "Repeating the key for #{name}")

          press(tool, key)
          assert_bend(tool, instance, axis, 0, "Repeating the key for #{name} again")
        }
        assert_equal(0, @beeps)
      end

      def test_on_key_down_selecting_another_axis_starts_at_its_default_direction
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        press(tool, VK_RIGHT)
        assert_bend(tool, instance, X, 1)

        press(tool, VK_LEFT)
        press(tool, VK_RIGHT)

        assert_bend(tool, instance, X, 0)
      end

      def test_on_key_down_refuses_an_axis_without_length
        instance = create_flat_instance(Z)
        tool = TrueBendTool.new(instance)

        assert(press(tool, VK_UP), 'Up arrow handled')

        assert_equal(1, @beeps)
        assert_bend(tool, instance, X, 0)
      end

      def test_on_key_down_refuses_every_other_axis_of_a_line
        instance = create_line_instance(Y)
        tool = TrueBendTool.new(instance)
        assert_bend(tool, instance, Y, 0)

        press(tool, VK_RIGHT)
        press(tool, VK_UP)

        assert_equal(2, @beeps)
        assert_bend(tool, instance, Y, 0)
      end

      def test_on_key_down_ignores_other_keys
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        refute(press(tool, VK_DOWN), 'Down arrow')
        refute(press(tool, VK_SHIFT), 'Shift')

        assert_equal(0, @beeps)
        assert_bend(tool, instance, X, 0)
      end

      def test_on_key_down_resets_the_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 5
        assert(bender_of(tool).bending?)

        press(tool, VK_LEFT)

        refute(bender_of(tool).bending?)
      end

      def test_on_key_down_keeps_the_number_of_segments
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        without_user_feedback {
          tool.onUserText('8s', Sketchup.active_model.active_view)
        }
        assert_equal(8, bender_of(tool).subdivisions)

        press(tool, VK_LEFT)
        assert_equal(8, bender_of(tool).subdivisions, 'Another axis')

        press(tool, VK_LEFT)
        assert_equal(8, bender_of(tool).subdivisions, 'Other direction')
      end


      def test_click_bounds_edge_selects_the_axis_it_runs_along
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)

        click(tool, edge_position(instance, Y))
        assert_bend(tool, instance, Y, 0, 'Edge along green')

        click(tool, edge_position(instance, Z))
        assert_bend(tool, instance, Z, 0, 'Edge along blue')

        click(tool, edge_position(instance, X))
        assert_bend(tool, instance, X, 0, 'Edge along red')

        assert_equal(0, @beeps)
      end

      def test_click_bounds_edge_follows_the_axes_of_a_rotated_instance
        # Turned a quarter around blue, the red axis of the instance runs
        # along the green axis of the model.
        rotation = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
        instance = create_solid(X, rotation)
        look_at(instance)
        tool = TrueBendTool.new(instance)

        click(tool, edge_position(instance, Y))
        assert_bend(tool, instance, Y, 0, 'Edge along the green axis of the instance')

        click(tool, edge_position(instance, X))
        assert_bend(tool, instance, X, 0, 'Edge along the red axis of the instance')
      end

      def test_click_bounds_edge_again_switches_the_bend_direction
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)

        click(tool, edge_position(instance, X))

        assert_bend(tool, instance, X, 1)
      end

      def test_click_bounds_edge_needs_the_mouse_released_on_the_edge
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)

        click(tool, edge_position(instance, Y), empty_position)

        assert_bend(tool, instance, X, 0)
      end


      def test_drag_handle_bends_towards_the_front
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        look_at_handle(tool)

        drag_handle(tool, QUARTER_CIRCLE_DRAG)

        bender = bender_of(tool)
        assert_in_delta(90.degrees, bender.angle, drag_tolerance(tool))
        assert(bender.concave?)
        assert_vector(Geom::Vector3d.new(0, -1, 0), bender.direction.normalize)
        refute(handle_of(tool).drag?)
      end

      def test_drag_handle_into_the_instance_bends_away_from_the_front
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        look_at_handle(tool)

        drag_handle(tool, -QUARTER_CIRCLE_DRAG)

        bender = bender_of(tool)
        assert_in_delta(90.degrees, bender.angle, drag_tolerance(tool))
        assert(bender.convex?)
        assert_vector(Geom::Vector3d.new(0, 1, 0), bender.direction.normalize)
      end

      def test_drag_handle_again_adds_to_the_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        look_at_handle(tool)

        drag_handle(tool, QUARTER_CIRCLE_DRAG / 2.0)
        drag_handle(tool, QUARTER_CIRCLE_DRAG / 2.0)

        assert_in_delta(90.degrees, bender_of(tool).angle, drag_tolerance(tool, 2))
        assert(bender_of(tool).concave?)
      end

      def test_drag_the_other_handle_bends_towards_the_top
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        front, top = handles_of(tool)
        look_at_handle(tool, top)

        drag_handle(tool, QUARTER_CIRCLE_DRAG, top)

        bender = bender_of(tool)
        assert_in_delta(90.degrees, bender.angle, drag_tolerance(tool))
        assert(bender.concave?)
        assert_vector(Z_AXIS, bender.direction.normalize)
        assert_same(top, handle_of(tool), 'The handle that is dragged is the one in use')
        assert_equal(TrueBendTool::ACTIVE_HANDLE_COLOR, top.color)
        assert_equal(TrueBendTool::INACTIVE_HANDLE_COLOR, front.color)
      end

      def test_drag_the_other_handle_starts_a_new_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = QUARTER_CIRCLE_DRAG
        top = handles_of(tool).last
        look_at_handle(tool, top)

        drag_handle(tool, QUARTER_CIRCLE_DRAG / 2.0, top)

        assert_in_delta(45.degrees, bender_of(tool).angle, drag_tolerance(tool))
        assert_vector(Z_AXIS, bender_of(tool).direction.normalize)
      end

      def test_drag_the_other_handle_keeps_the_number_of_segments
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        type(tool, '8s')
        top = handles_of(tool).last
        look_at_handle(tool, top)

        drag_handle(tool, QUARTER_CIRCLE_DRAG, top)

        assert_equal(8, bender_of(tool).subdivisions)
      end

      def test_drag_beside_the_handle_does_nothing
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)
        start = empty_position

        drag(tool, start, [start[0] - 50, start[1] - 50])

        refute(bender_of(tool).bending?)
        refute(bender_of(tool).can_bend?)
      end


      def test_on_user_text_without_a_bend_beeps
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        type(tool, '45')

        assert_equal(1, @beeps)
        refute(bender_of(tool).bending?)
      end

      def test_on_user_text_sets_the_angle
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '45')

        bender = bender_of(tool)
        assert_in_delta(45.degrees, bender.angle, 1.0e-9)
        assert(bender.concave?)
        assert_equal(0, @beeps)
        assert_empty(@messages)
        assert_in_delta(bender.distance.to_f, handle_of(tool).distance.to_f, TOLERANCE, 'Handle')
      end

      def test_on_user_text_sets_the_angle_with_degrees_suffix
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '60deg')

        assert_in_delta(60.degrees, bender_of(tool).angle, 1.0e-9)
      end

      def test_on_user_text_keeps_the_side_the_bend_is_on
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = -1

        type(tool, '45')

        assert_in_delta(45.degrees, bender_of(tool).angle, 1.0e-9)
        assert(bender_of(tool).convex?)
      end

      def test_on_user_text_length_sets_the_distance
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '2"')

        bender = bender_of(tool)
        assert_in_delta(2.0, bender.distance.to_f, TOLERANCE)
        assert_in_delta(360.degrees * 2.0 / (100.0 / Math::PI), bender.angle, 1.0e-9)
        assert(bender.concave?)
        assert_in_delta(2.0, handle_of(tool).distance.to_f, TOLERANCE, 'Handle')
      end

      def test_on_user_text_plain_number_after_a_length_is_a_distance
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '2"')

        type(tool, '3')

        # A plain number is in the units of the model. With large units it is
        # more than the distance that bends the solid full circle, which is
        # where the bend stops.
        bender = bender_of(tool)
        expected = ['3'.to_l.to_f, bender.max_bend_distance.to_f].min
        assert_in_delta(expected, bender.distance.to_f, TOLERANCE)
      end

      def test_on_user_text_degrees_after_a_length_goes_back_to_angles
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '2"')
        type(tool, '30deg')

        type(tool, '45')

        assert_in_delta(45.degrees, bender_of(tool).angle, 1.0e-9)
      end

      def test_on_user_text_negative_length_bends_the_other_way
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '-2"')

        bender = bender_of(tool)
        assert_in_delta(2.0, bender.distance.to_f, TOLERANCE)
        assert(bender.convex?)
      end

      def test_on_user_text_length_stops_at_a_full_circle
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '100"')

        bender = bender_of(tool)
        assert_in_delta(360.degrees, bender.angle, 1.0e-9)
        assert_in_delta(100.0 / Math::PI, bender.distance.to_f, TOLERANCE)
      end

      def test_on_user_text_sets_the_number_of_segments
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        angle = bender_of(tool).angle

        type(tool, '8s')

        assert_equal(8, bender_of(tool).subdivisions)
        assert_in_delta(angle, bender_of(tool).angle, 1.0e-9)
        assert_empty(@messages)
      end

      def test_on_user_text_sets_the_number_of_segments_without_a_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        type(tool, '8s')

        assert_equal(8, bender_of(tool).subdivisions)
        assert_equal(0, @beeps)
      end

      def test_on_user_text_refuses_fewer_than_two_segments
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        type(tool, '1s')

        assert_equal(24, bender_of(tool).subdivisions)
        assert_equal(1, @messages.size)
      end

      def test_on_user_text_reports_a_length_it_cannot_read
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, 'two"')

        assert_equal(1, @messages.size)
        assert_in_delta(1.0, bender_of(tool).distance.to_f, TOLERANCE)
      end


      def test_on_cancel_resets_the_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 5

        without_user_feedback {
          tool.onCancel(0, Sketchup.active_model.active_view)
        }

        refute(bender_of(tool).bending?)
        refute(bender_of(tool).can_bend?)
        assert_same_points(solid_corners(X), local_positions(instance))
      end

      def test_on_return_bends_the_instance
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = QUARTER_CIRCLE_DRAG

        without_user_feedback {
          tool.onReturn(Sketchup.active_model.active_view)
        }

        assert_bent_quarter_circle(instance, tool)
      end

      def test_on_return_without_a_bend_leaves_the_instance
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        without_user_feedback {
          tool.onReturn(Sketchup.active_model.active_view)
        }

        assert_same_points(solid_corners(X), local_positions(instance))
      end

      def test_on_return_puts_the_tool_away
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        model = Sketchup.active_model
        without_user_feedback { model.tools.push_tool(tool) }
        tool_id = model.tools.active_tool_id
        # The tool also puts itself away when the model changes, which the bend
        # itself does. Without that, only the commit is left to do it.
        model.remove_observer(tool.instance_variable_get(:@observer))
        bender_of(tool).distance = QUARTER_CIRCLE_DRAG

        without_user_feedback { tool.onReturn(model.active_view) }

        refute_equal(tool_id, model.tools.active_tool_id)
      ensure
        model.select_tool(nil) if model
      end

      def test_on_return_bends_in_one_undo_step
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = QUARTER_CIRCLE_DRAG
        without_user_feedback {
          tool.onReturn(Sketchup.active_model.active_view)
        }

        Sketchup.undo

        assert_same_points(solid_corners(X), local_positions(instance))
      end

      def test_double_click_bends_the_instance
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = QUARTER_CIRCLE_DRAG
        view = Sketchup.active_model.active_view
        position = empty_position

        # SketchUp gives the tool the first click, and then the double click
        # in place of the mouse button going down the second time.
        drag(tool, position, position)
        without_user_feedback {
          tool.onLButtonDoubleClick(0, *position, view)
          tool.onLButtonUp(0, *position, view)
        }

        assert_bent_quarter_circle(instance, tool)
      end


      def test_activate_watches_the_model
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        without_user_feedback { tool.activate }

        assert(watches?(tool, Sketchup.active_model))
      ensure
        Sketchup.active_model.remove_observer(tool.instance_variable_get(:@observer)) if tool
      end

      def test_deactivate_stops_watching_the_model
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        model = Sketchup.active_model
        without_user_feedback { tool.activate }

        without_user_feedback { tool.deactivate(model.active_view) }

        refute(watches?(tool, model))
      end

      def test_change_to_the_model_puts_the_tool_away
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        model = Sketchup.active_model
        without_user_feedback { model.tools.push_tool(tool) }
        tool_id = model.tools.active_tool_id

        without_user_feedback {
          model.start_operation('Change', true)
          model.entities.add_cpoint(ORIGIN)
          model.commit_operation
        }

        refute_equal(tool_id, model.tools.active_tool_id)
        refute(watches?(tool, model))
      ensure
        model.select_tool(nil) if model
      end

    end # class
  end # module
end # module
