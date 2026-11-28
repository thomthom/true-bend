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

      # Stands in for the view when the tool is asked to draw outside of a
      # redraw. It measures like the view it wraps, draws nothing, and keeps
      # the tooltip it is given.
      class ViewSpy

        DRAWING = %i[
          draw draw2d draw_points draw_text draw_line draw_lines draw_polyline
          drawing_color= line_width= line_stipple= set_color_from_line
        ].freeze

        attr_accessor :tooltip

        def initialize(view)
          @view = view
          @tooltip = ''
        end

        # The tool only takes a view.
        def is_a?(klass)
          klass == Sketchup::View || super
        end

        DRAWING.each { |name|
          define_method(name) { |*_arguments| nil }
        }

        def method_missing(name, *arguments, &block)
          return super unless @view.respond_to?(name)

          @view.public_send(name, *arguments, &block)
        end

        def respond_to_missing?(name, include_private = false)
          @view.respond_to?(name, include_private) || super
        end

      end

      # A `ViewSpy` that keeps what it is asked to draw.
      class RecordingViewSpy < ViewSpy

        # @return [Array<Array(Symbol, Array, Hash)>] The name, the arguments
        #   and the keyword arguments of each call.
        attr_reader :calls

        def initialize(view)
          super
          @calls = []
        end

        %i[draw draw2d draw_points drawing_color=].each { |name|
          define_method(name) { |*arguments, **options|
            @calls << [name, arguments, options]
            nil
          }
        }

      end

      def setup
        isolate_settings
        start_with_empty_model
        @beeps = 0
        @messages = []
      end

      def teardown
        restore_settings
      end


      # Keeps the tests from writing to the user's preferences, and starts each
      # test from the default tool options.
      def isolate_settings
        @settings_cache = SETTINGS.instance_variable_get(:@cache).dup
        SETTINGS.define_singleton_method(:write) { |key, value| @cache[key] = value }
        SETTINGS.bend_input_mode = :angle
        SETTINGS.bend_segmented = true
        SETTINGS.bend_soft_smooth = true
        SETTINGS.debug_draw_global_mesh = false
        SETTINGS.debug_draw_local_mesh = false
        SETTINGS.debug_draw_mesh_points = false
        SETTINGS.debug_draw_see_through_faces = false
        SETTINGS.debug_face_opacity = 0.5
      end

      def restore_settings
        return unless @settings_cache

        SETTINGS.singleton_class.send(:remove_method, :write)
        SETTINGS.instance_variable_set(:@cache, @settings_cache)
      end

      # @param [TrueBendTool] tool
      # @param [Symbol] option
      # @return [Array(Numeric, Numeric)] The center of the option's button, in
      #   device pixels.
      def option_position(tool, option)
        buttons = tool.instance_variable_get(:@option_buttons)
        DPI.device_pixels(*buttons.center(option))
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

      # Double clicks the left mouse button in the viewport. SketchUp gives
      # the tool the first click, and then the double click in place of the
      # mouse button going down the second time.
      #
      # @param [TrueBendTool] tool
      # @param [Array(Numeric, Numeric)] position In device pixels.
      def double_click(tool, position)
        view = Sketchup.active_model.active_view
        click(tool, position)
        without_user_feedback {
          tool.onLButtonDoubleClick(0, *position, view)
          tool.onLButtonUp(0, *position, view)
        }
      end

      # Bends a quarter of a circle, away from the face the bend is set up
      # towards.
      #
      # @param [TrueBendTool] tool
      def bend_quarter_circle_away(tool)
        bender = bender_of(tool)
        bender.distance = -bender.max_bend_distance / 4.0
      end

      # Asserts that the tool has the instance bent a quarter of a circle, away
      # from the face the bend is set up towards.
      #
      # @param [TrueBendTool] tool
      # @param [String] message
      def assert_quarter_circle_away(tool, message = nil)
        bender = bender_of(tool)
        assert_in_delta(90.degrees, bender.angle, 1.0e-9, message)
        assert(bender.convex?, message)
        assert_vector(axes_of(tool).normal.reverse, bender.direction.normalize, message)
        expected_distance = bender.max_bend_distance.to_f / 4.0
        assert_in_delta(expected_distance, bender.direction.length.to_f, TOLERANCE, message)
      end

      # Asserts that the tool has the instance bent by the given distance, away
      # from the face the bend is set up towards.
      #
      # @param [TrueBendTool] tool
      # @param [Float] distance
      # @param [String] message
      def assert_distance_away(tool, distance, message = nil)
        bender = bender_of(tool)
        assert_in_delta(distance, bender.distance.to_f, TOLERANCE, message)
        assert(bender.convex?, message)
        assert_vector(axes_of(tool).normal.reverse, bender.direction.normalize, message)
        expected_angle = 360.degrees * distance / bender.max_bend_distance.to_f
        assert_in_delta(expected_angle, bender.angle, 1.0e-9, message)
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
        # The bender doesn't tell which direction it is set up to bend in, but
        # it bends that way when there is no bend. The bend there was is put
        # back, as the tool keeps it from one axis to the next.
        direction = bender.direction
        angle = bender.angle
        bender.reset
        bender.distance = 1
        assert_vector(expected.normal, bender.direction, message)
        bender.bend(direction)
        bender.angle = angle
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

      # @param [TrueBendTool] tool
      # @param [Integer] axis
      # @return [Array(Numeric, Numeric)] The middle of the button for the
      #   axis, in device pixels.
      def button_position(tool, axis)
        buttons = tool.instance_variable_get(:@axis_buttons)
        DPI.device_pixels(*buttons.center(axis))
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

      def test_on_key_down_keeps_the_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 0)
        assert_quarter_circle_away(tool, 'Another axis')

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 1)
        assert_quarter_circle_away(tool, 'Other direction')
      end

      def test_on_key_down_without_a_bend_leaves_it_unbent
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        press(tool, VK_LEFT)

        refute(bender_of(tool).bending?)
        refute(bender_of(tool).can_bend?)
      end

      def test_on_key_down_keeps_an_angle_that_was_typed
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        without_user_feedback {
          tool.onUserText('60', Sketchup.active_model.active_view)
        }
        assert_in_delta(60.degrees, bender_of(tool).angle, 1.0e-9)

        press(tool, VK_UP)

        assert_in_delta(60.degrees, bender_of(tool).angle, 1.0e-9)
        assert(bender_of(tool).concave?)
      end

      def test_on_key_down_keeps_a_distance_that_was_typed
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)
        type(tool, '1"')
        assert_in_delta(1.0, bender_of(tool).distance.to_f, TOLERANCE)

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 0)
        assert_distance_away(tool, 1.0, 'Another axis')

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 1)
        assert_distance_away(tool, 1.0, 'Other direction')
      end

      def test_on_key_down_stops_a_typed_distance_at_a_full_circle
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '10"')
        assert_in_delta(10.0, bender_of(tool).distance.to_f, TOLERANCE)

        press(tool, VK_LEFT)

        bender = bender_of(tool)
        assert_in_delta(360.degrees, bender.angle, 1.0e-9)
        assert_in_delta(bender.max_bend_distance.to_f, bender.distance.to_f, TOLERANCE)
        assert(bender.concave?)
      end

      def test_on_key_down_keeps_a_radius_that_was_typed
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)
        type(tool, '50"r')
        assert_in_delta(50.0, bender_of(tool).radius.to_f, TOLERANCE)

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 0)
        assert_in_delta(50.0, bender_of(tool).radius.to_f, TOLERANCE, 'Another axis')
        assert(bender_of(tool).convex?, 'Another axis')

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 1)
        assert_in_delta(50.0, bender_of(tool).radius.to_f, TOLERANCE, 'Other direction')
        assert(bender_of(tool).convex?, 'Other direction')
      end

      def test_on_key_down_keeps_a_sagitta_that_was_typed
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)
        type(tool, '1"sg')
        assert_in_delta(1.0, bender_of(tool).sagitta.to_f, TOLERANCE)

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 0)
        assert_in_delta(1.0, bender_of(tool).sagitta.to_f, TOLERANCE, 'Another axis')
        assert(bender_of(tool).convex?, 'Another axis')

        press(tool, VK_LEFT)
        assert_bend(tool, instance, Y, 1)
        assert_in_delta(1.0, bender_of(tool).sagitta.to_f, TOLERANCE, 'Other direction')
        assert(bender_of(tool).convex?, 'Other direction')
      end

      def test_on_key_down_stops_a_typed_sagitta_at_the_largest_sagitta
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '10"sg')
        assert_in_delta(10.0, bender_of(tool).sagitta.to_f, TOLERANCE)

        press(tool, VK_LEFT)

        bender = bender_of(tool)
        assert_in_delta(Bender::MAX_SAGITTA_ANGLE, bender.angle, 1.0e-9)
        assert_in_delta(bender.max_sagitta.to_f, bender.sagitta.to_f, TOLERANCE)
      end

      # Setting the sagitta of such a bend would bend it by a smaller angle with
      # the same sagitta.
      def test_on_key_down_keeps_the_angle_of_a_bend_beyond_the_largest_sagitta
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '1"sg')
        assert_equal(:sagitta, SETTINGS.bend_input_mode)
        bender = bender_of(tool)
        bender.distance = bender.max_bend_distance * 300.0 / 360.0
        assert_in_delta(300.degrees, bender.angle, 1.0e-9)

        press(tool, VK_RIGHT)

        assert_bend(tool, instance, X, 1)
        assert_in_delta(300.degrees, bender_of(tool).angle, 1.0e-9)
      end

      def test_on_key_down_keeps_the_angle_once_an_angle_is_typed_after_a_distance
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '1"')
        type(tool, '60deg')

        press(tool, VK_LEFT)

        assert_in_delta(60.degrees, bender_of(tool).angle, 1.0e-9)
      end

      def test_click_axis_button_keeps_a_distance_that_was_typed
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)
        type(tool, '1"')

        click(tool, button_position(tool, Z))

        assert_bend(tool, instance, Z, 0)
        assert_distance_away(tool, 1.0)
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


      def test_click_axis_button_selects_the_axis
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        click(tool, button_position(tool, Y))
        assert_bend(tool, instance, Y, 0, 'Green button')

        click(tool, button_position(tool, Z))
        assert_bend(tool, instance, Z, 0, 'Blue button')

        click(tool, button_position(tool, X))
        assert_bend(tool, instance, X, 0, 'Red button')

        assert_equal(0, @beeps)
      end

      def test_click_axis_button_again_switches_the_bend_direction
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        click(tool, button_position(tool, X))
        assert_bend(tool, instance, X, 1, 'Second click')

        click(tool, button_position(tool, X))
        assert_bend(tool, instance, X, 0, 'Third click')
      end

      def test_click_axis_button_refuses_an_axis_without_length
        instance = create_flat_instance(Z)
        tool = TrueBendTool.new(instance)

        click(tool, button_position(tool, Z))

        assert_equal(1, @beeps)
        assert_bend(tool, instance, X, 0)
      end

      def test_click_axis_button_needs_the_mouse_released_on_the_button
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        click(tool, button_position(tool, Y), button_position(tool, Z))

        assert_bend(tool, instance, X, 0)
      end

      def test_click_axis_button_keeps_the_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)

        click(tool, button_position(tool, Y))

        assert_bend(tool, instance, Y, 0)
        assert_quarter_circle_away(tool)
      end

      def test_double_click_axis_button_is_two_clicks_and_doesnt_commit
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)

        double_click(tool, button_position(tool, Y))

        assert_bend(tool, instance, Y, 1)
        assert_quarter_circle_away(tool)
        assert_same_points(solid_corners(X), local_positions(instance))
      end

      def test_click_option_button_sets_what_a_typed_number_is
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        click(tool, option_position(tool, :radius))
        type(tool, '40')
        expected = ['40'.to_l.to_f, 100.0 / 360.degrees].max
        assert_in_delta(expected, bender_of(tool).radius.to_f, TOLERANCE, 'Radius')
        assert_equal(:radius, SETTINGS.bend_input_mode)

        click(tool, option_position(tool, :sagitta))
        type(tool, '2')
        expected = ['2'.to_l.to_f, bender_of(tool).max_sagitta.to_f].min
        assert_in_delta(expected, bender_of(tool).sagitta.to_f, TOLERANCE, 'Sagitta')
        assert_equal(:sagitta, SETTINGS.bend_input_mode)

        click(tool, option_position(tool, :distance))
        type(tool, '3')
        expected = ['3'.to_l.to_f, bender_of(tool).max_bend_distance.to_f].min
        assert_in_delta(expected, bender_of(tool).distance.to_f, TOLERANCE, 'Distance')
        assert_equal(:distance, SETTINGS.bend_input_mode)

        click(tool, option_position(tool, :angle))
        type(tool, '45')
        assert_in_delta(45.degrees, bender_of(tool).angle, 1.0e-9, 'Angle')
        assert_equal(:angle, SETTINGS.bend_input_mode)
      end

      def test_click_option_button_keeps_the_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)

        OptionButtons::OPTIONS.each { |option|
          click(tool, option_position(tool, option))

          assert_bend(tool, instance, X, 0, option.to_s)
          assert_quarter_circle_away(tool, option.to_s)
        }
      end

      def test_click_segmented_button_switches_between_segments_and_a_true_curve
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        click(tool, option_position(tool, :segmented))
        refute(bender_of(tool).segmented, 'First click')
        refute(SETTINGS.bend_segmented?, 'First click')

        click(tool, option_position(tool, :segmented))
        assert(bender_of(tool).segmented, 'Second click')
        assert(SETTINGS.bend_segmented?, 'Second click')
      end

      def test_click_soft_smooth_button_switches_softening_of_the_segment_edges
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        click(tool, option_position(tool, :soft_smooth))
        refute(bender_of(tool).soft_smooth, 'First click')
        refute(SETTINGS.bend_soft_smooth?, 'First click')

        click(tool, option_position(tool, :soft_smooth))
        assert(bender_of(tool).soft_smooth, 'Second click')
        assert(SETTINGS.bend_soft_smooth?, 'Second click')
        assert_equal(0, @beeps)
      end

      def test_click_soft_smooth_button_is_refused_for_a_true_curve
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        click(tool, option_position(tool, :segmented))

        click(tool, option_position(tool, :soft_smooth))

        assert_equal(1, @beeps)
        assert(bender_of(tool).soft_smooth)
        assert(SETTINGS.bend_soft_smooth?)
      end

      def test_click_option_button_needs_the_mouse_released_on_the_button
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        click(tool, option_position(tool, :radius), option_position(tool, :distance))
        click(tool, option_position(tool, :segmented), button_position(tool, Y))

        assert_equal(:angle, SETTINGS.bend_input_mode)
        assert(bender_of(tool).segmented)
        assert_bend(tool, instance, X, 0)
      end

      def test_double_click_option_button_is_two_clicks_and_doesnt_commit
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)
        click(tool, option_position(tool, :segmented))

        double_click(tool, option_position(tool, :segmented))

        refute(bender_of(tool).segmented)
        assert_quarter_circle_away(tool)
        assert_same_points(solid_corners(X), local_positions(instance))
      end

      def test_option_buttons_keep_what_they_are_set_to_when_choosing_another_axis
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        click(tool, option_position(tool, :segmented))

        press(tool, VK_LEFT)

        assert_bend(tool, instance, Y, 0)
        refute(bender_of(tool).segmented)
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

      def test_click_bounds_edge_keeps_the_bend
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)

        click(tool, edge_position(instance, Z))

        assert_bend(tool, instance, Z, 0)
        assert_quarter_circle_away(tool)
      end

      def test_double_click_bounds_edge_is_two_clicks_and_doesnt_commit
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)

        double_click(tool, edge_position(instance, Y))

        assert_bend(tool, instance, Y, 1)
        assert_quarter_circle_away(tool)
        assert_same_points(solid_corners(X), local_positions(instance))
      end

      def test_click_bounds_edge_needs_the_mouse_released_on_the_edge
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)

        click(tool, edge_position(instance, Y), empty_position)

        assert_bend(tool, instance, X, 0)
      end

      def test_click_needs_the_mouse_released_on_the_control_it_was_pressed_on
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)

        click(tool, button_position(tool, Y), edge_position(instance, Y))
        assert_bend(tool, instance, X, 0, 'From the green button to a green edge')

        click(tool, edge_position(instance, Y), button_position(tool, Y))
        assert_bend(tool, instance, X, 0, 'From a green edge to the green button')
      end

      def test_click_away_from_buttons_and_edges_keeps_the_bend
        instance = create_solid(X)
        look_at(instance)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 5

        click(tool, empty_position)

        assert(bender_of(tool).bending?)
        assert_bend(tool, instance, X, 0)
      end


      def test_get_extents_covers_the_reference_segment_and_the_handles
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)

        extents = without_user_feedback { tool.getExtents }

        segment = bender_of(tool).segment
        assert(extents.contains?(segment.start), 'Start of the reference segment')
        assert(extents.contains?(segment.end), 'End of the reference segment')
        handles_of(tool).each_with_index { |handle, index|
          assert(extents.contains?(handle.origin), "Handle #{index}")
        }
      end

      # SketchUp clips what the tool draws outside of these extents.
      def test_get_extents_covers_the_bent_faces
        skip('The face preview needs SketchUp 2020.') unless FaceDrawer.supported?
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 127.mm

        extents = without_user_feedback { tool.getExtents }

        triangles = bender_of(tool).bent_triangles(FaceColors.new(instance.model))
        points = triangles.flat_map(&:positions)
        refute_empty(points)
        points.each { |point|
          assert(extents.contains?(point), "The extents don't contain #{point.to_a.inspect}")
        }
      end

      # Has the tool draw, in a style that fills faces with their materials.
      #
      # @param [TrueBendTool] tool
      # @param [Integer] render_mode The value of the "RenderMode" rendering
      #   option to draw with.
      # @return [Array<Array(Symbol, Array, Hash)>] See
      #   {RecordingViewSpy#calls}.
      def drawing_calls(tool, render_mode = 2)
        skip('Needs vertex normals.') unless FaceDrawer.supported?
        options = Sketchup.active_model.rendering_options
        original_mode = options['RenderMode']
        options['RenderMode'] = render_mode
        view = RecordingViewSpy.new(Sketchup.active_model.active_view)
        without_user_feedback { tool.draw(view) }
        view.calls
      ensure
        options['RenderMode'] = original_mode if original_mode
      end

      # @param [Array<Array(Symbol, Array, Hash)>] calls
      # @return [Array<Array>] The colour, the points and the normals, if any,
      #   of each call that draws triangles.
      def drawn_triangles(calls)
        color = nil
        calls.each_with_object([]) { |(name, arguments, options), triangles|
          color = arguments[0] if name == :drawing_color=
          next unless name == :draw && arguments[0] == GL_TRIANGLES

          triangles << [color, arguments[1], options[:normals]]
        }
      end

      def test_draw_shades_the_bent_faces_half_transparent
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 127.mm

        triangles = drawn_triangles(drawing_calls(tool))

        shaded = triangles.select { |_, _, normals| normals }
        refute_empty(shaded)
        shaded.each { |color, points, normals|
          assert_equal(127, color.alpha, 'Opacity')
          assert_equal(points.size, normals.size, 'A normal for each point')
          assert_equal(0, points.size % 3, 'Three points for each triangle')
        }
        assert_equal(bender_of(tool).bent_triangles(FaceColors.new(instance.model)).size * 3,
                     shaded.inject(0) { |sum, (_, points, _)| sum + points.size })
      end

      def test_draw_draws_no_faces_without_a_bend
        tool = TrueBendTool.new(create_solid(X))

        assert_empty(drawn_triangles(drawing_calls(tool)))
      end

      def test_draw_draws_no_faces_in_a_wireframe_style
        tool = TrueBendTool.new(create_solid(X))
        bender_of(tool).distance = 127.mm

        assert_empty(drawn_triangles(drawing_calls(tool, FaceColors::WIREFRAME)))
      end

      # Lines drawn after the faces would be hidden where they are behind the
      # faces. The buttons are not in model space.
      def test_draw_draws_the_faces_last_in_model_space
        tool = TrueBendTool.new(create_solid(X))
        bender_of(tool).distance = 127.mm

        calls = drawing_calls(tool)

        first = calls.index { |name, arguments, _| name == :draw && arguments[0] == GL_TRIANGLES }
        refute_nil(first)
        after = calls[first..-1].select { |name, _, _| name == :draw }
        assert_equal([GL_TRIANGLES], after.map { |_, arguments, _| arguments[0] }.uniq)
        assert_includes(calls[first..-1].map(&:first), :draw2d, 'The buttons')
      end

      # The faces behind other faces fail the depth test, because the depth of
      # all of them is drawn first, without a colour.
      def test_draw_draws_the_depth_of_the_faces_before_the_faces
        tool = TrueBendTool.new(create_solid(X))
        bender_of(tool).distance = 127.mm

        triangles = drawn_triangles(drawing_calls(tool))

        color, points, normals = triangles.first
        assert_nil(normals, 'The depth is not shaded')
        assert_equal(0, color.alpha, 'The depth has no colour')
        shaded_points = triangles.drop(1).inject(0) { |sum, (_, shaded, _)| sum + shaded.size }
        assert_equal(shaded_points, points.size)
        assert(triangles.drop(1).all? { |_, _, shaded_normals| shaded_normals })
      end

      # A point keeps its position in the viewport only if it moves along its
      # line of sight.
      def test_draw_moves_the_depth_of_the_faces_half_a_pixel_away_from_the_camera
        skip('The face preview needs SketchUp 2020.') unless FaceDrawer.supported?
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 127.mm
        view = Sketchup.active_model.active_view
        [false, true].each { |perspective|
          look_at(instance)
          view.camera.perspective = perspective
          camera = view.camera

          triangles = drawn_triangles(drawing_calls(tool))

          _, depth, = triangles.first
          faces = triangles.drop(1).flat_map { |_, points, _| points }
          refute_empty(faces, "Perspective: #{perspective}")
          assert_equal(faces.size, depth.size, "Perspective: #{perspective}")
          faces.zip(depth) { |face_point, depth_point|
            offset = face_point.vector_to(depth_point)
            half_pixel = HighDpiView.new(view).pixels_to_model(1, face_point).to_f / 2.0
            assert_in_delta(half_pixel, offset % camera.direction, half_pixel * 1.0e-6,
                            "Perspective: #{perspective}")
            line_of_sight = perspective ? camera.eye.vector_to(face_point) : camera.direction
            assert_in_delta(0.0, offset.angle_between(line_of_sight), 1.0e-6,
                            "Perspective: #{perspective}")
          }
        }
      end

      def test_draw_debug_setting_draws_the_faces_behind_other_faces
        tool = TrueBendTool.new(create_solid(X))
        bender_of(tool).distance = 127.mm
        SETTINGS.debug_draw_see_through_faces = true

        triangles = drawn_triangles(drawing_calls(tool))

        refute_empty(triangles)
        assert(triangles.all? { |_, _, normals| normals }, 'The depth is not drawn first')
      end

      # @return [Sketchup::Group] The test solid, with every face red on the
      #   outside of the solid and blue on the inside.
      def create_two_sided_solid
        instance = create_solid(X)
        center = instance.definition.bounds.center
        instance.entities.grep(Sketchup::Face) { |face|
          face.reverse! if face.normal % center.vector_to(face.bounds.center) < 0.0
          face.material = 'red'
          face.back_material = 'blue'
        }
        instance
      end

      # A transparent face hides the faces behind it that are drawn after it,
      # so the ones that face away from the camera are drawn first.
      def test_draw_draws_the_faces_that_face_away_first_in_the_color_of_their_back
        instance = create_two_sided_solid
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 127.mm
        # In a parallel projection the direction of the camera decides which
        # side of a face it sees, not its position. This camera is lower than
        # the top of the solid and looks slightly down, so it sees the top
        # from above.
        eye = instance.bounds.center.offset(Geom::Vector3d.new(0, -200, -15))
        target = eye.offset(Geom::Vector3d.new(0, 200, -20))
        view = Sketchup.active_model.active_view
        [false, true].each { |perspective|
          if perspective
            look_at(instance)
          else
            view.camera = Sketchup::Camera.new(eye, target, Z_AXIS, false)
          end
          camera = view.camera

          triangles = drawn_triangles(drawing_calls(tool))

          shaded = triangles.select { |_, _, normals| normals }
          colors = shaded.map { |color, _, _| color.to_a[0, 3] }
          assert_equal([[0, 0, 255], [255, 0, 0]], colors, "Perspective: #{perspective}")
          shaded.each { |color, points, _|
            points.each_slice(3) { |a, b, c|
              to_camera = perspective ? a.vector_to(camera.eye) : camera.direction.reverse
              faces_camera = ((b - a) * (c - a)) % to_camera > 0.0
              assert_equal(color.red == 255, faces_camera, "Perspective: #{perspective}")
            }
          }
        }
      end

      def test_draw_draws_no_faces_with_a_fully_transparent_material
        instance = create_solid(X)
        instance.material = 'red'
        instance.material.alpha = 0.0
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 127.mm

        triangles = drawn_triangles(drawing_calls(tool))

        assert_empty(triangles)
      end

      # A face that is not drawn must not hide the faces behind it either.
      def test_draw_leaves_fully_transparent_faces_out_of_the_depth_of_the_faces
        instance = create_solid(X)
        invisible = Sketchup.active_model.materials.add('Invisible')
        invisible.alpha = 0.0
        face = instance.entities.grep(Sketchup::Face).first
        face.material = invisible
        face.back_material = invisible
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 127.mm
        all_points = bender_of(tool).bent_triangles(FaceColors.new(instance.model)).size * 3

        triangles = drawn_triangles(drawing_calls(tool))

        _, depth_points, = triangles.first
        shaded_points = triangles.drop(1).inject(0) { |sum, (_, points, _)| sum + points.size }
        assert_operator(shaded_points, :<, all_points, 'The invisible face is not drawn')
        assert_equal(shaded_points, depth_points.size)
      end

      def test_draw_debug_setting_sets_the_opacity_of_the_faces
        tool = TrueBendTool.new(create_solid(X))
        bender_of(tool).distance = 127.mm
        { 0.25 => 63, 1.0 => 255 }.each { |opacity, alpha|
          SETTINGS.debug_face_opacity = opacity

          triangles = drawn_triangles(drawing_calls(tool))

          shaded = triangles.select { |_, _, normals| normals }
          refute_empty(shaded, "Opacity: #{opacity}")
          shaded.each { |color, _, _| assert_equal(alpha, color.alpha, "Opacity: #{opacity}") }
        }
      end

      def test_draw_debug_setting_draws_the_points_of_the_bent_edges
        tool = TrueBendTool.new(create_solid(X))
        bender_of(tool).distance = 127.mm
        calls = lambda {
          view = RecordingViewSpy.new(Sketchup.active_model.active_view)
          without_user_feedback { tool.draw(view) }
          view.calls
        }
        edge_points = proc { |name, arguments, _| name == :draw_points && arguments[3] == 'maroon' }
        lines = proc { |name, arguments, _| name == :draw && arguments[0] == GL_LINES }
        without_points = calls.call
        assert_equal(0, without_points.count(&edge_points))

        SETTINGS.debug_draw_mesh_points = true
        with_points = calls.call

        assert_equal(1, with_points.count(&edge_points))
        assert_equal(with_points.count(&lines), without_points.count(&lines), 'Lines')
        assert_equal(with_points.count { |name, _, _| name == :draw_points } - 1,
                     without_points.count { |name, _, _| name == :draw_points }, 'Other points')
      end

      # From Ruby 3.0 a method that passes its arguments on has to pass
      # keyword arguments on as such. `Sketchup::View#draw` ignores a Hash.
      def test_high_dpi_view_passes_keyword_arguments_on
        spy = RecordingViewSpy.new(Sketchup.active_model.active_view)
        points = [ORIGIN, Geom::Point3d.new(1, 0, 0), Geom::Point3d.new(0, 1, 0)]
        normals = [Z_AXIS, Z_AXIS, Z_AXIS]

        HighDpiView.new(spy).draw(GL_TRIANGLES, points, normals: normals)

        assert_equal([[:draw, [GL_TRIANGLES, points], { normals: normals }]], spy.calls)
      end

      # @param [TrueBendTool] tool
      # @return [String] The tooltip the tool leaves on the view when it draws.
      def tooltip_after_draw(tool)
        view = ViewSpy.new(Sketchup.active_model.active_view)
        without_user_feedback { tool.draw(view) }
        view.tooltip
      end

      def test_draw_shows_the_measures_of_the_bend_in_the_tooltip
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 5

        tooltip = tooltip_after_draw(tool)

        assert_match(/\AAngle: .+\nRadius: .+\nBend: .+\nSagitta: .+\z/, tooltip)
      end

      def test_draw_shows_a_positive_sagitta_for_a_negative_angle
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '-45')
        sagitta = bender_of(tool).sagitta
        assert_operator(sagitta, :<, 0)

        tooltip = tooltip_after_draw(tool)

        assert_equal("Sagitta: #{sagitta.abs.to_l}", tooltip.lines.last)
      end

      def test_draw_shows_what_a_click_would_do_in_the_tooltip_while_bent
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 5
        view = Sketchup.active_model.active_view
        without_user_feedback {
          tool.onMouseMove(0, *button_position(tool, Y), view)
        }

        tooltip = tooltip_after_draw(tool)

        assert_equal('Bend along the green axis (Left Arrow)', tooltip)
      end


      def test_draw_shows_what_an_option_button_does_in_the_tooltip
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 5
        view = Sketchup.active_model.active_view
        without_user_feedback {
          tool.onMouseMove(0, *option_position(tool, :radius), view)
        }

        tooltip = tooltip_after_draw(tool)

        assert_equal('Type the radius of the bend (500mmr)', tooltip)
      end

      def test_draw_shows_what_the_sagitta_button_does_in_the_tooltip
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 5
        view = Sketchup.active_model.active_view
        without_user_feedback {
          tool.onMouseMove(0, *option_position(tool, :sagitta), view)
        }

        tooltip = tooltip_after_draw(tool)

        assert_equal('Type the sagitta of the bend (50mmsg)', tooltip)
      end

      def test_draw_says_why_the_soft_smooth_button_is_unavailable
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        click(tool, option_position(tool, :segmented))
        view = Sketchup.active_model.active_view
        without_user_feedback {
          tool.onMouseMove(0, *option_position(tool, :soft_smooth), view)
        }

        tooltip = tooltip_after_draw(tool)

        assert_equal(TrueBendOptions::SOFT_SMOOTH_UNAVAILABLE, tooltip)
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

      def test_drag_the_other_handle_keeps_the_bend_and_adds_to_it
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = QUARTER_CIRCLE_DRAG
        top = handles_of(tool).last
        look_at_handle(tool, top)

        drag_handle(tool, QUARTER_CIRCLE_DRAG / 2.0, top)

        assert_in_delta(135.degrees, bender_of(tool).angle, drag_tolerance(tool))
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

      def test_on_user_text_radius_sets_the_radius
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '50"r')

        bender = bender_of(tool)
        assert_in_delta(50.0, bender.radius.to_f, TOLERANCE)
        # angle = arc length / radius
        assert_in_delta(100.0 / 50.0, bender.angle, 1.0e-9)
        assert(bender.concave?)
        assert_equal(0, @beeps)
        assert_empty(@messages)
        assert_in_delta(bender.distance.to_f, handle_of(tool).distance.to_f, TOLERANCE, 'Handle')
      end

      def test_on_user_text_plain_number_after_a_radius_is_a_radius
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '50"r')

        type(tool, '40')

        # A unitless number is in model units. In small units it is below the
        # minimum radius and gets clamped to a full circle.
        expected = ['40'.to_l.to_f, 100.0 / 360.degrees].max
        assert_in_delta(expected, bender_of(tool).radius.to_f, TOLERANCE)
      end

      def test_on_user_text_length_after_a_radius_goes_back_to_distances
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '50"r')

        type(tool, '2"')

        assert_in_delta(2.0, bender_of(tool).distance.to_f, TOLERANCE)
      end

      def test_on_user_text_degrees_after_a_radius_goes_back_to_angles
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '50"r')
        type(tool, '30deg')

        type(tool, '45')

        assert_in_delta(45.degrees, bender_of(tool).angle, 1.0e-9)
      end

      def test_on_user_text_negative_radius_bends_the_other_way
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '-50"r')

        bender = bender_of(tool)
        assert_in_delta(50.0, bender.radius.to_f, TOLERANCE)
        assert(bender.convex?)
      end

      def test_on_user_text_radius_stops_at_a_full_circle
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '5"r')

        bender = bender_of(tool)
        assert_in_delta(360.degrees, bender.angle, 1.0e-9)
        assert_in_delta(100.0 / 360.degrees, bender.radius.to_f, TOLERANCE)
      end

      def test_on_user_text_refuses_a_radius_of_zero
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '0"r')

        assert_equal(1, @beeps)
        assert_in_delta(1.0, bender_of(tool).distance.to_f, TOLERANCE)
      end

      def test_on_user_text_reports_a_radius_it_cannot_read
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, 'two"r')

        assert_equal(1, @messages.size)
        assert_in_delta(1.0, bender_of(tool).distance.to_f, TOLERANCE)
      end

      def test_on_user_text_sagitta_sets_the_sagitta
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '10"sg')

        bender = bender_of(tool)
        assert_in_delta(10.0, bender.sagitta.to_f, TOLERANCE)
        assert_in_delta(100.0, bender.arc_length.to_f, TOLERANCE)
        assert(bender.concave?)
        assert_equal(0, @beeps)
        assert_empty(@messages)
        assert_in_delta(bender.distance.to_f, handle_of(tool).distance.to_f, TOLERANCE, 'Handle')
      end

      def test_on_user_text_plain_number_after_a_sagitta_is_a_sagitta
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '10"sg')

        type(tool, '5')

        # A unitless number is in model units. In large units it is above the
        # largest sagitta and gets clamped to it.
        bender = bender_of(tool)
        expected = ['5'.to_l.to_f, bender.max_sagitta.to_f].min
        assert_in_delta(expected, bender.sagitta.to_f, TOLERANCE)
      end

      def test_on_user_text_length_after_a_sagitta_goes_back_to_distances
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '10"sg')
        assert_equal(:sagitta, SETTINGS.bend_input_mode)

        type(tool, '2"')

        assert_in_delta(2.0, bender_of(tool).distance.to_f, TOLERANCE)
      end

      def test_on_user_text_radius_after_a_sagitta_goes_back_to_radii
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '10"sg')
        assert_equal(:sagitta, SETTINGS.bend_input_mode)

        type(tool, '50"r')

        assert_in_delta(50.0, bender_of(tool).radius.to_f, TOLERANCE)
        assert_equal(:radius, SETTINGS.bend_input_mode)
      end

      def test_on_user_text_negative_sagitta_bends_the_other_way
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '-10"sg')

        bender = bender_of(tool)
        assert_in_delta(10.0, bender.sagitta.to_f, TOLERANCE)
        assert(bender.convex?)
      end

      def test_on_user_text_sagitta_stops_at_the_largest_sagitta
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '50"sg')

        bender = bender_of(tool)
        assert_in_delta(Bender::MAX_SAGITTA_ANGLE, bender.angle, 1.0e-9)
        assert_in_delta(bender.max_sagitta.to_f, bender.sagitta.to_f, TOLERANCE)
        assert_equal(0, @beeps)
        assert_empty(@messages)
      end

      def test_on_user_text_sagitta_of_zero_removes_the_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '0"sg')

        refute(bender_of(tool).bending?)
        assert_equal(0, @beeps)
        assert_empty(@messages)
        # Drawing must not raise an error.
        tooltip_after_draw(tool)
      end

      def test_on_user_text_sagitta_after_a_sagitta_of_zero_bends_to_the_same_side
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bend_quarter_circle_away(tool)
        type(tool, '0"sg')

        type(tool, '10"sg')

        bender = bender_of(tool)
        assert_in_delta(10.0, bender.sagitta.to_f, TOLERANCE)
        assert(bender.convex?)
        assert_equal(0, @beeps)
        assert_empty(@messages)
      end

      def test_on_user_text_reports_a_sagitta_it_cannot_read
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, 'two"sg')

        assert_equal(1, @messages.size)
        assert_in_delta(1.0, bender_of(tool).distance.to_f, TOLERANCE)
        assert_equal(:angle, SETTINGS.bend_input_mode)
      end

      def test_on_user_text_remembers_a_sagitta_for_the_next_use_of_the_tool
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '10"sg')

        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '5')

        bender = bender_of(tool)
        expected = ['5'.to_l.to_f, bender.max_sagitta.to_f].min
        assert_in_delta(expected, bender.sagitta.to_f, TOLERANCE)
        assert_equal(:sagitta, SETTINGS.bend_input_mode)
      end

      def test_measurements_box_shows_the_sagitta
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        labels = []
        values = []

        Sketchup.stub(:vcb_label=, ->(label) { labels << label }) {
          Sketchup.stub(:vcb_value=, ->(value) { values << value }) {
            type(tool, '-10"sg')
          }
        }

        assert_equal('Sagitta', labels.last)
        assert_in_delta(10.0, values.last.to_f, TOLERANCE)
      end

      def test_measurements_box_shows_a_sagitta_of_zero_without_a_bend
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        values = []

        Sketchup.stub(:vcb_value=, ->(value) { values << value }) {
          click(tool, option_position(tool, :sagitta))
        }

        assert_equal(0.0, values.last.to_f)
      end

      def test_on_user_text_remembers_a_distance_for_the_next_use_of_the_tool
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '2"')

        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '3')

        bender = bender_of(tool)
        expected = ['3'.to_l.to_f, bender.max_bend_distance.to_f].min
        assert_in_delta(expected, bender.distance.to_f, TOLERANCE)
        assert_equal(:distance, SETTINGS.bend_input_mode)
      end

      def test_on_user_text_remembers_a_radius_for_the_next_use_of_the_tool
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '50"r')

        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '40')

        expected = ['40'.to_l.to_f, 100.0 / 360.degrees].max
        assert_in_delta(expected, bender_of(tool).radius.to_f, TOLERANCE)
        assert_equal(:radius, SETTINGS.bend_input_mode)
      end

      def test_on_user_text_remembers_angles_for_the_next_use_of_the_tool
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '2"')
        type(tool, '30deg')

        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '45')

        assert_in_delta(45.degrees, bender_of(tool).angle, 1.0e-9)
        assert_equal(:angle, SETTINGS.bend_input_mode)
      end

      def test_on_user_text_is_an_angle_when_what_is_remembered_makes_no_sense
        SETTINGS.bend_input_mode = :nonsense
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '45')

        assert_in_delta(45.degrees, bender_of(tool).angle, 1.0e-9)
      end

      def test_on_user_text_invalid_input_keeps_the_input_mode
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1

        type(tool, '45d')

        assert_equal(1, @messages.size)
        assert_equal(:angle, SETTINGS.bend_input_mode)
        type(tool, '60')
        assert_in_delta(60.degrees, bender_of(tool).angle, 1.0e-9)
      end

      def test_on_user_text_persists_the_input_mode_typed_last_in_any_tool
        instance = create_solid(X)
        first = TrueBendTool.new(instance)
        second = TrueBendTool.new(instance)
        bender_of(first).distance = 1
        bender_of(second).distance = 1
        type(first, '50"r')

        type(second, '45deg')

        assert_equal(:angle, SETTINGS.bend_input_mode)
      end

      def test_measurements_box_shows_a_positive_radius_for_a_negative_angle
        instance = create_solid(X)
        tool = TrueBendTool.new(instance)
        bender_of(tool).distance = 1
        type(tool, '-45')
        values = []

        Sketchup.stub(:vcb_value=, ->(value) { values << value }) {
          click(tool, option_position(tool, :radius))
        }

        assert_operator(values.last.to_f, :>, 0)
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


      def test_activate_watches_the_model_of_the_instance
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
