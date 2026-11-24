#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'
require_relative '../lib/test_utilities'

module TT::Plugins::TrueBend
  module Tests
    class TC_Bender < TestUp::TestCase

      include TrueBendTestUtilities

      TRANSLATION = Geom::Transformation.translation(Geom::Vector3d.new(30, -40, 50))
      QUARTER_TURN_ABOUT_BLUE = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
      ROTATION_ABOUT_BLUE = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 37.degrees)
      SCALING = Geom::Transformation.scaling(2, 0.5, 1.5)

      # The ways the instances being bent are placed in the model. None of them
      # shear the instance: scaling is applied before rotating.
      PLACEMENTS = {
        'unrotated'                           => IDENTITY,
        'moved'                               => TRANSLATION,
        'rotated_about_blue'                  => QUARTER_TURN_ABOUT_BLUE,
        'scaled_non_uniformly'                => SCALING,
        'mirrored_along_red'                  => Geom::Transformation.scaling(-1, 1, 1),
        'mirrored_along_green'                => Geom::Transformation.scaling(1, -1, 1),
        'moved_rotated_about_blue_and_scaled' => TRANSLATION * ROTATION_ABOUT_BLUE * SCALING,
      }.freeze

      def setup
        start_with_empty_model
      end

      def teardown
        # ...
      end


      # Bends the test solid and checks every vertex of the result against
      # where a true circular bend puts it.
      #
      # @param [Geom::Transformation] transformation
      # @param [Boolean] towards Whether to bend towards or away from the front
      #   of the instance.
      def assert_true_bend(transformation, towards)
        instance = create_solid(X, transformation)
        setup = bend_setup(instance)
        segment_points = setup.segment.points
        drag = drag_vector(setup, towards)
        original = sliced_solid_points(X).map { |point| point.transform(transformation) }
        expected = true_bend(original, segment_points, drag)

        bent = commit_bend(instance, setup, drag)

        assert_same_points(expected, world_positions(bent))
      end

      PLACEMENTS.each { |placement, transformation|
        [true, false].each { |towards|
          name = "test_commit_#{placement}_#{towards ? 'towards' : 'away_from'}_the_front"
          define_method(name) {
            assert_true_bend(transformation, towards)
          }
        }
      }

      def test_commit_true_curve_puts_every_vertex_on_the_arc
        instance = create_solid(X)
        add_edge_loop(instance, X, 0.4)
        setup = bend_setup(instance)
        drag = drag_vector(setup, true)
        original = sliced_solid_points(X, 4) + solid_section(X, 0.4)
        expected = true_bend(original, setup.segment.points, drag)

        bent = commit_bend(instance, setup, drag, subdivisions: 4) { |bender|
          bender.segmented = false
        }

        assert_same_points(expected, world_positions(bent))
      end

      # In a segmented bend the instance is straight between the slicing
      # planes. A vertex between two planes keeps its angle around the centre
      # of the bend, and ends up on the straight line between where the planes
      # on either side of it put the edge it is on.
      def test_commit_segmented_keeps_vertices_between_slices_on_straight_segments
        instance = create_solid(X, tapered: false)
        add_edge_loop(instance, X, 0.4, tapered: false)
        setup = bend_setup(instance)
        drag = drag_vector(setup, true)
        segment_points = setup.segment.points
        # With four segments, 0.4 along the solid is 0.6 of the way from the
        # slice at 0.25 to the slice at 0.5.
        segment_angle = bend_angle(segment_points, drag) / 4
        before = Math.sin(segment_angle * 0.6)
        after = Math.sin(segment_angle * 0.4)
        ratio = before / (before + after)
        slice1 = true_bend(solid_section(X, 0.25, tapered: false), segment_points, drag)
        slice2 = true_bend(solid_section(X, 0.5, tapered: false), segment_points, drag)
        between = slice1.zip(slice2).map { |point1, point2|
          Geom.linear_combination(1.0 - ratio, point1, ratio, point2)
        }
        slices = true_bend(sliced_solid_points(X, 4, tapered: false), segment_points, drag)

        bent = commit_bend(instance, setup, drag, subdivisions: 4) { |bender|
          bender.segmented = true
        }

        assert_same_points(slices + between, world_positions(bent))
      end

      def test_commit_by_angle
        instance = create_solid(X)
        setup = bend_setup(instance)
        drag = drag_vector(setup, true)
        expected = true_bend(sliced_solid_points(X), setup.segment.points, drag, 60.degrees)

        bent = commit_bend(instance, setup, drag) { |bender|
          bender.angle = 60.degrees
        }

        assert_same_points(expected, world_positions(bent))
      end

      def test_commit_bends_nested_instances
        placement = Geom::Transformation.translation(Geom::Vector3d.new(3, 4, 5)) *
                    Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees)
        parent = Sketchup.active_model.entities.add_group
        create_solid(X, placement, entities: parent.entities)
        setup = bend_setup(parent)
        drag = drag_vector(setup, true)
        original = sliced_solid_points(X).map { |point| point.transform(placement) }
        expected = true_bend(original, setup.segment.points, drag)

        bent = commit_bend(parent, setup, drag)

        child = bent.definition.entities.grep(Sketchup::Group).first
        actual = local_positions(child).map { |point| point.transform(child.transformation) }
        assert_same_points(expected, actual)
      end

      def test_commit_bends_every_instance_of_a_component
        instance = create_solid(X).to_component
        offset = Geom::Transformation.translation(Geom::Vector3d.new(0, 200, 0))
        other = Sketchup.active_model.entities.add_instance(instance.definition, offset)
        setup = bend_setup(instance)
        drag = drag_vector(setup, true)
        expected = true_bend(sliced_solid_points(X), setup.segment.points, drag)

        bent = commit_bend(instance, setup, drag)

        assert_same_points(expected, world_positions(bent))
        assert_equal(bent.definition, other.definition)
      end

      def test_commit_leaves_nothing_else_in_the_model
        instance = create_solid(X)
        setup = bend_setup(instance)

        bent = commit_bend(instance, setup, drag_vector(setup, true))

        assert_equal([bent], Sketchup.active_model.entities.to_a)
        assert_empty(bent.definition.entities.grep(Sketchup::Group))
      end

      def test_commit_softens_the_edges_from_slicing
        instance = create_solid(X, tapered: false)
        setup = bend_setup(instance)

        bent = commit_bend(instance, setup, drag_vector(setup, true)) { |bender|
          bender.segmented = true
          bender.soft_smooth = true
        }

        edges = bent.definition.entities.grep(Sketchup::Edge)
        soft = edges.select { |edge| edge.soft? && edge.smooth? }
        # The planes at the ends of the solid don't cut it, so each of the
        # others adds an edge to each of the four sides.
        assert_equal((SUBDIVISIONS - 1) * 4, soft.size)
        assert_equal(8 + (SUBDIVISIONS * 4), (edges - soft).size, 'Edges of the solid')
      end

      def test_commit_segmented_without_soft_smooth_leaves_the_edges_from_slicing_hard
        instance = create_solid(X, tapered: false)
        setup = bend_setup(instance)

        bent = commit_bend(instance, setup, drag_vector(setup, true)) { |bender|
          bender.segmented = true
          bender.soft_smooth = false
        }

        edges = bent.definition.entities.grep(Sketchup::Edge)
        assert_equal(8 + (SUBDIVISIONS * 4) + ((SUBDIVISIONS - 1) * 4), edges.size)
        assert_empty(edges.select { |edge| edge.soft? || edge.smooth? })
      end

      def test_commit_makes_a_group_unique
        instance = create_solid(X)
        copy = instance.copy
        setup = bend_setup(instance)

        bent = commit_bend(instance, setup, drag_vector(setup, true))

        refute_equal(copy.definition, bent.definition)
        assert_same_points(solid_corners(X), local_positions(copy))
      end


      # @return [Bender] For a segment 100" long, running along the red axis
      #   from the origin, bending towards the front.
      def create_bender
        instance = create_solid(X)
        segment = Segment.new(ORIGIN, Geom::Point3d.new(100, 0, 0))
        Bender.new(instance, segment, Y_AXIS.reverse)
      end

      def test_bend_sets_the_angle_from_the_distance_dragged
        bender = create_bender
        full_circle_diameter = 100.0 / Math::PI

        bender.bend(Geom::Vector3d.new(0, -full_circle_diameter / 4.0, 0))

        assert_in_delta(90.degrees, bender.angle, 1.0e-9)
        assert_in_delta(full_circle_diameter / 4.0, bender.distance.to_f, TOLERANCE)
        assert(bender.bending?)
        assert(bender.can_bend?)
      end

      def test_bend_stops_at_a_full_circle
        bender = create_bender

        bender.bend(Geom::Vector3d.new(0, -500, 0))

        assert_in_delta(360.degrees, bender.angle, 1.0e-9)
        assert_in_delta(100.0 / Math::PI, bender.distance.to_f, TOLERANCE)
        assert_in_delta(100.0 / Math::PI, bender.max_bend_distance.to_f, TOLERANCE)
      end

      def test_bend_half_circle_measurements
        bender = create_bender
        # Half a circle with a circumference twice the length of the segment.
        radius = 100.0 / Math::PI

        bender.bend(Geom::Vector3d.new(0, -radius / 2.0, 0))

        assert_in_delta(180.degrees, bender.angle, 1.0e-9)
        assert_in_delta(radius, bender.radius.to_f, TOLERANCE)
        assert_in_delta(radius * 2.0, bender.diameter.to_f, TOLERANCE)
        assert_in_delta(radius * 2.0, bender.chord.to_f, TOLERANCE)
        assert_in_delta(radius, bender.sagitta.to_f, TOLERANCE)
        assert_in_delta(100.0, bender.arc_length.to_f, TOLERANCE)
      end

      def test_bend_quarter_circle_measurements
        bender = create_bender
        radius = 100.0 / (Math::PI / 2.0)

        bender.bend(Geom::Vector3d.new(0, 100.0 / Math::PI / 4.0, 0))

        assert_in_delta(radius, bender.radius.to_f, TOLERANCE)
        assert_in_delta(radius * Math.sqrt(2.0), bender.chord.to_f, TOLERANCE)
        assert_in_delta(radius * (1.0 - Math.sqrt(0.5)), bender.sagitta.to_f, TOLERANCE)
        assert_in_delta(100.0, bender.arc_length.to_f, TOLERANCE)
      end

      def test_origin_is_the_centre_of_the_bend
        bender = create_bender
        radius = 100.0 / Math::PI

        bender.bend(Geom::Vector3d.new(0, -radius / 2.0, 0))
        assert_point(Geom::Point3d.new(50, -radius, 0), bender.origin, 'Towards the front')

        bender.bend(Geom::Vector3d.new(0, radius / 2.0, 0))
        assert_point(Geom::Point3d.new(50, radius, 0), bender.origin, 'Away from the front')
      end

      def test_concave_when_bending_towards_the_normal
        bender = create_bender

        bender.bend(Geom::Vector3d.new(0, -5, 0))
        assert(bender.concave?)
        refute(bender.convex?)

        bender.bend(Geom::Vector3d.new(0, 5, 0))
        refute(bender.concave?)
        assert(bender.convex?)
      end

      def test_reset
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, -5, 0))

        bender.reset

        assert_equal(0.0, bender.angle)
        assert_equal(0.0, bender.distance.to_f)
        refute(bender.bending?)
        refute(bender.can_bend?)
        assert_point(Geom::Point3d.new(50, 0, 0), bender.origin)
      end

      def test_set_distance_bends_towards_the_normal_when_there_is_no_bend
        bender = create_bender

        bender.distance = 5

        assert_vector(Geom::Vector3d.new(0, -5, 0), bender.direction)
        assert(bender.concave?)
        assert_in_delta(5.0, bender.distance.to_f, TOLERANCE)
      end

      def test_set_distance_negative_bends_away_from_the_normal
        bender = create_bender

        bender.distance = -5

        assert_vector(Geom::Vector3d.new(0, 5, 0), bender.direction)
        assert(bender.convex?)
        assert_in_delta(5.0, bender.distance.to_f, TOLERANCE)
      end

      def test_set_distance_keeps_the_direction_of_the_bend
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, 2, 0))

        bender.distance = 5

        assert_vector(Geom::Vector3d.new(0, 5, 0), bender.direction)
        assert(bender.convex?)
      end

    end # class
  end # module
end # module
