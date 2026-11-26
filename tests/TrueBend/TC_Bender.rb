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

      ARBITRARY_AXIS = Geom::Vector3d.new(1, 2, 3)
      ARBITRARY_ROTATION = Geom::Transformation.rotation(ORIGIN, ARBITRARY_AXIS, 37.degrees)
      TRANSLATION = Geom::Transformation.translation(Geom::Vector3d.new(30, -40, 50))
      QUARTER_TURN_ABOUT_RED = Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees)
      QUARTER_TURN_ABOUT_GREEN = Geom::Transformation.rotation(ORIGIN, Y_AXIS, 90.degrees)
      QUARTER_TURN_ABOUT_BLUE = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 90.degrees)
      ROTATION_ABOUT_BLUE = Geom::Transformation.rotation(ORIGIN, Z_AXIS, 37.degrees)
      SCALING = Geom::Transformation.scaling(2, 0.5, 1.5)
      SCALED_AND_MIRRORED = Geom::Transformation.scaling(-2, 0.5, 1.5)
      ROTATED_SCALED_AND_MIRRORED = TRANSLATION * ARBITRARY_ROTATION * SCALED_AND_MIRRORED

      # The ways the instances being bent are placed in the model. None of them
      # shear the instance: scaling is applied before rotating.
      PLACEMENTS = {
        'unrotated'                           => IDENTITY,
        'moved'                               => TRANSLATION,
        'rotated_about_red'                   => QUARTER_TURN_ABOUT_RED,
        'rotated_about_green'                 => QUARTER_TURN_ABOUT_GREEN,
        'rotated_about_blue'                  => QUARTER_TURN_ABOUT_BLUE,
        'rotated_about_arbitrary_axis'        => TRANSLATION * ARBITRARY_ROTATION,
        'scaled_non_uniformly'                => SCALING,
        'mirrored_along_red'                  => Geom::Transformation.scaling(-1, 1, 1),
        'mirrored_along_green'                => Geom::Transformation.scaling(1, -1, 1),
        'mirrored_along_blue'                 => Geom::Transformation.scaling(1, 1, -1),
        'moved_rotated_about_blue_and_scaled' => TRANSLATION * ROTATION_ABOUT_BLUE * SCALING,
        'rotated_scaled_and_mirrored'         => ROTATED_SCALED_AND_MIRRORED,
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
      # @param [Integer] axis The axis of the instance to bend along.
      # @param [Integer] face_index Which of the faces the instance can bend
      #   towards along that axis.
      # @param [Boolean] towards Whether to bend towards or away from that face.
      def assert_true_bend(transformation, axis, face_index, towards)
        instance = create_solid(axis, transformation)
        axes = BendAxes.along(instance, axis)[face_index]
        segment_points = axes.segment.points
        drag = drag_vector(axes, towards)
        original = sliced_solid_points(axis).map { |point| point.transform(transformation) }
        expected = true_bend(original, segment_points, drag)

        bent = commit_bend(instance, axes, drag)

        assert_same_points(expected, world_positions(bent))
      end

      PLACEMENTS.each { |placement, transformation|
        BendAxes::FACES.each_with_index { |faces, axis|
          faces.each_with_index { |face, face_index|
            [true, false].each { |towards|
              name = "test_commit_#{placement}_along_#{AXIS_NAMES[axis]}_" \
                     "#{towards ? 'towards' : 'away_from'}_#{FACE_NAMES[face]}"
              define_method(name) {
                assert_true_bend(transformation, axis, face_index, towards)
              }
            }
          }
        }
      }

      # Regression test: the bend used to be made in a plane found from the
      # direction of the reference segment alone, which for an instance tilted
      # about its red axis was not the plane of the bend.
      def test_commit_instance_tilted_about_its_red_axis_bends_like_an_unrotated_one
        tilt = Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees)
        [true, false].each { |towards|
          results = [IDENTITY, tilt].map { |transformation|
            instance = create_solid(BendAxes::X, transformation)
            axes = BendAxes.along(instance, BendAxes::X).first
            local_positions(commit_bend(instance, axes, drag_vector(axes, towards)))
          }
          unrotated, tilted = results
          assert_same_points(unrotated, tilted,
                             "Bending #{towards ? 'towards' : 'away from'} the front")
        }
      end

      def test_commit_true_curve_puts_every_vertex_on_the_arc
        axis = BendAxes::X
        instance = create_solid(axis)
        add_edge_loop(instance, axis, 0.4)
        axes = BendAxes.along(instance, axis).first
        drag = drag_vector(axes, true)
        original = sliced_solid_points(axis, 4) + solid_section(axis, 0.4)
        expected = true_bend(original, axes.segment.points, drag)

        bent = commit_bend(instance, axes, drag, subdivisions: 4) { |bender|
          bender.segmented = false
        }

        assert_same_points(expected, world_positions(bent))
      end

      # In a segmented bend the instance is straight between the slicing
      # planes. A vertex between two planes keeps its angle around the centre
      # of the bend, and ends up on the straight line between where the planes
      # on either side of it put the edge it is on.
      def test_commit_segmented_keeps_vertices_between_slices_on_straight_segments
        axis = BendAxes::X
        instance = create_solid(axis, tapered: false)
        add_edge_loop(instance, axis, 0.4, tapered: false)
        axes = BendAxes.along(instance, axis).first
        drag = drag_vector(axes, true)
        segment_points = axes.segment.points
        # With four segments, 0.4 along the solid is 0.6 of the way from the
        # slice at 0.25 to the slice at 0.5.
        segment_angle = bend_angle(segment_points, drag) / 4
        before = Math.sin(segment_angle * 0.6)
        after = Math.sin(segment_angle * 0.4)
        ratio = before / (before + after)
        slice1 = true_bend(solid_section(axis, 0.25, tapered: false), segment_points, drag)
        slice2 = true_bend(solid_section(axis, 0.5, tapered: false), segment_points, drag)
        between = slice1.zip(slice2).map { |point1, point2|
          Geom.linear_combination(1.0 - ratio, point1, ratio, point2)
        }
        slices = true_bend(sliced_solid_points(axis, 4, tapered: false), segment_points, drag)

        bent = commit_bend(instance, axes, drag, subdivisions: 4) { |bender|
          bender.segmented = true
        }

        assert_same_points(slices + between, world_positions(bent))
      end

      def test_commit_by_angle
        axis = BendAxes::X
        instance = create_solid(axis)
        axes = BendAxes.along(instance, axis).first
        drag = drag_vector(axes, true)
        expected = true_bend(sliced_solid_points(axis), axes.segment.points, drag, 60.degrees)

        bent = commit_bend(instance, axes, drag) { |bender|
          bender.angle = 60.degrees
        }

        assert_same_points(expected, world_positions(bent))
      end

      def test_commit_bends_nested_instances
        axis = BendAxes::X
        placement = Geom::Transformation.translation(Geom::Vector3d.new(3, 4, 5)) *
                    Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees)
        parent = Sketchup.active_model.entities.add_group
        create_solid(axis, placement, entities: parent.entities)
        axes = BendAxes.along(parent, axis).first
        drag = drag_vector(axes, true)
        original = sliced_solid_points(axis).map { |point| point.transform(placement) }
        expected = true_bend(original, axes.segment.points, drag)

        bent = commit_bend(parent, axes, drag)

        child = bent.definition.entities.grep(Sketchup::Group).first
        actual = local_positions(child).map { |point| point.transform(child.transformation) }
        assert_same_points(expected, actual)
      end

      def test_commit_bends_every_instance_of_a_component
        axis = BendAxes::X
        instance = create_solid(axis).to_component
        offset = Geom::Transformation.translation(Geom::Vector3d.new(0, 200, 0))
        other = Sketchup.active_model.entities.add_instance(instance.definition, offset)
        axes = BendAxes.along(instance, axis).first
        drag = drag_vector(axes, true)
        expected = true_bend(sliced_solid_points(axis), axes.segment.points, drag)

        bent = commit_bend(instance, axes, drag)

        assert_same_points(expected, world_positions(bent))
        assert_equal(bent.definition, other.definition)
      end

      def test_commit_leaves_nothing_else_in_the_model
        instance = create_solid(BendAxes::X)
        axes = BendAxes.along(instance, BendAxes::X).first

        bent = commit_bend(instance, axes, drag_vector(axes, true))

        assert_equal([bent], Sketchup.active_model.entities.to_a)
        assert_empty(bent.definition.entities.grep(Sketchup::Group))
      end

      def test_commit_softens_the_edges_from_slicing
        instance = create_solid(BendAxes::X, tapered: false)
        axes = BendAxes.along(instance, BendAxes::X).first

        bent = commit_bend(instance, axes, drag_vector(axes, true)) { |bender|
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
        instance = create_solid(BendAxes::X, tapered: false)
        axes = BendAxes.along(instance, BendAxes::X).first

        bent = commit_bend(instance, axes, drag_vector(axes, true)) { |bender|
          bender.segmented = true
          bender.soft_smooth = false
        }

        edges = bent.definition.entities.grep(Sketchup::Edge)
        assert_equal(8 + (SUBDIVISIONS * 4) + ((SUBDIVISIONS - 1) * 4), edges.size)
        assert_empty(edges.select { |edge| edge.soft? || edge.smooth? })
      end

      def test_commit_makes_a_group_unique
        instance = create_solid(BendAxes::X)
        copy = instance.copy
        axes = BendAxes.along(instance, BendAxes::X).first

        bent = commit_bend(instance, axes, drag_vector(axes, true))

        refute_equal(copy.definition, bent.definition)
        assert_same_points(solid_corners(BendAxes::X), local_positions(copy))
      end


      # @return [Bender] For a segment 100" long, running along the red axis
      #   from the origin, bending towards the front.
      def create_bender
        instance = create_solid(BendAxes::X)
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

      # Sets up a bend of the test solid along one axis from a bend of it along
      # another, and checks every vertex of the result against where a true
      # circular bend of the same angle puts it.
      #
      # @param [Boolean] towards Whether the bends are towards or away from
      #   the faces they are set up for.
      def assert_match_angle_is_a_true_bend(towards)
        instance = create_solid(BendAxes::X)
        first_axes = BendAxes.along(instance, BendAxes::Y).first
        first = Bender.new(instance, first_axes.segment, first_axes.normal)
        first.bend(drag_vector(first_axes, towards))
        axes = BendAxes.along(instance, BendAxes::X).first
        drag = towards ? axes.normal : axes.normal.reverse
        expected = true_bend(sliced_solid_points(BendAxes::X), axes.segment.points, drag,
                             first.angle)

        # The drag given here is replaced by the bend that is copied.
        bent = commit_bend(instance, axes, drag) { |bender|
          bender.match_angle(first)
        }

        assert_same_points(expected, world_positions(bent))
      end

      def test_match_angle_bends_by_the_same_angle_towards_the_normal
        assert_match_angle_is_a_true_bend(true)
      end

      def test_match_angle_bends_by_the_same_angle_away_from_the_normal
        assert_match_angle_is_a_true_bend(false)
      end

      def test_match_angle_keeps_the_angle_for_a_segment_of_another_length
        other = create_bender
        other.bend(Geom::Vector3d.new(0, 100.0 / Math::PI / 4.0, 0))
        instance = create_solid(BendAxes::X)
        segment = Segment.new(ORIGIN, Geom::Point3d.new(0, 0, 40))
        bender = Bender.new(instance, segment, X_AXIS)

        bender.match_angle(other)

        assert_in_delta(90.degrees, bender.angle, 1.0e-9)
        assert_vector(Geom::Vector3d.new(-40.0 / Math::PI / 4.0, 0, 0), bender.direction)
        assert(bender.convex?)
      end

      def test_match_angle_keeps_an_angle_that_was_set
        other = create_bender
        other.distance = 5
        other.angle = 60.degrees
        bender = create_bender

        bender.match_angle(other)

        assert_in_delta(60.degrees, bender.angle, 1.0e-9)
        assert_in_delta(100.0 / Math::PI / 6.0, bender.distance.to_f, TOLERANCE)
        assert(bender.concave?)
      end

      def test_match_angle_without_a_bend_resets
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, -5, 0))

        bender.match_angle(create_bender)

        refute(bender.bending?)
        refute(bender.can_bend?)
      end

      # @return [Bender] One with a reference segment shorter than that of
      #   `create_bender`, which a full circle takes a distance of
      #   `40.0 / Math::PI` to bend.
      def create_short_bender
        instance = create_solid(BendAxes::X)
        segment = Segment.new(ORIGIN, Geom::Point3d.new(0, 0, 40))
        Bender.new(instance, segment, X_AXIS)
      end

      def test_match_distance_keeps_the_distance_for_a_segment_of_another_length
        other = create_bender
        other.bend(Geom::Vector3d.new(0, 5, 0))
        bender = create_short_bender

        bender.match_distance(other)

        assert_in_delta(5.0, bender.distance.to_f, TOLERANCE)
        assert_in_delta(360.degrees * 5.0 / (40.0 / Math::PI), bender.angle, 1.0e-9)
        assert_vector(Geom::Vector3d.new(-5, 0, 0), bender.direction)
        assert(bender.convex?)
      end

      def test_match_distance_bends_towards_the_normal_like_the_other
        other = create_bender
        other.bend(Geom::Vector3d.new(0, -5, 0))
        bender = create_short_bender

        bender.match_distance(other)

        assert_vector(Geom::Vector3d.new(5, 0, 0), bender.direction)
        assert(bender.concave?)
      end

      def test_match_distance_stops_at_a_full_circle
        other = create_bender
        other.bend(Geom::Vector3d.new(0, -20, 0))
        bender = create_short_bender

        bender.match_distance(other)

        assert_in_delta(360.degrees, bender.angle, 1.0e-9)
        assert_in_delta(40.0 / Math::PI, bender.distance.to_f, TOLERANCE)
      end

      def test_match_distance_keeps_the_distance_of_an_angle_that_was_set
        other = create_bender
        other.distance = 5
        other.angle = 60.degrees
        bender = create_bender

        bender.match_distance(other)

        assert_in_delta(100.0 / Math::PI / 6.0, bender.distance.to_f, TOLERANCE)
        assert_in_delta(60.degrees, bender.angle, 1.0e-9)
        assert(bender.concave?)
      end

      def test_match_distance_without_a_bend_resets
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, -5, 0))

        bender.match_distance(create_bender)

        refute(bender.bending?)
        refute(bender.can_bend?)
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

      # @param [Float] length The length of the reference segment.
      # @param [Float] radius
      # @return [Float] The bend distance that gives the radius.
      def distance_for_radius(length, radius)
        (length / Math::PI) * (length / radius) / 360.degrees
      end

      def test_set_radius_bends_towards_the_normal_when_there_is_no_bend
        bender = create_bender

        bender.radius = 50

        # angle = arc length / radius
        assert_in_delta(100.0 / 50.0, bender.angle, 1.0e-9)
        assert_in_delta(50.0, bender.radius.to_f, TOLERANCE)
        assert_in_delta(100.0, bender.arc_length.to_f, TOLERANCE)
        distance = distance_for_radius(100.0, 50.0)
        assert_vector(Geom::Vector3d.new(0, -distance, 0), bender.direction)
        assert(bender.concave?)
      end

      def test_set_radius_negative_bends_away_from_the_normal
        bender = create_bender

        bender.radius = -50

        assert_in_delta(50.0, bender.radius.to_f, TOLERANCE)
        distance = distance_for_radius(100.0, 50.0)
        assert_vector(Geom::Vector3d.new(0, distance, 0), bender.direction)
        assert(bender.convex?)
      end

      def test_set_radius_keeps_the_direction_of_the_bend
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, 2, 0))

        bender.radius = 50

        assert_in_delta(50.0, bender.radius.to_f, TOLERANCE)
        assert(bender.convex?)
      end

      def test_set_radius_stops_at_a_full_circle
        bender = create_bender

        bender.radius = 5

        assert_in_delta(360.degrees, bender.angle, 1.0e-9)
        assert_in_delta(100.0 / 360.degrees, bender.radius.to_f, TOLERANCE)
      end

      def test_match_radius_keeps_the_radius_for_a_segment_of_another_length
        other = create_bender
        other.radius = -50
        bender = create_short_bender

        bender.match_radius(other)

        assert_in_delta(50.0, bender.radius.to_f, TOLERANCE)
        assert_in_delta(40.0 / 50.0, bender.angle, 1.0e-9)
        distance = distance_for_radius(40.0, 50.0)
        assert_vector(Geom::Vector3d.new(-distance, 0, 0), bender.direction)
        assert(bender.convex?)
      end

      def test_match_radius_bends_towards_the_normal_like_the_other
        other = create_bender
        other.radius = 50
        bender = create_short_bender

        bender.match_radius(other)

        distance = distance_for_radius(40.0, 50.0)
        assert_vector(Geom::Vector3d.new(distance, 0, 0), bender.direction)
        assert(bender.concave?)
      end

      def test_match_radius_stops_at_a_full_circle
        # This radius is valid for the short segment and too small for the long
        # one.
        other = create_short_bender
        other.radius = 7
        bender = create_bender

        bender.match_radius(other)

        assert_in_delta(360.degrees, bender.angle, 1.0e-9)
        assert_in_delta(100.0 / 360.degrees, bender.radius.to_f, TOLERANCE)
      end

      def test_match_radius_without_a_bend_resets
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, -5, 0))

        bender.match_radius(create_bender)

        refute(bender.bending?)
        refute(bender.can_bend?)
      end

      # @param [Float] length The length of the reference segment.
      # @param [Float] angle In radians.
      # @return [Float] The bend distance that gives the angle.
      def distance_for_angle(length, angle)
        (length / Math::PI) * angle / 360.degrees
      end

      def test_sagitta_is_zero_without_a_bend
        assert_equal(0.0, create_bender.sagitta.to_f)
      end

      def test_set_sagitta_bends_towards_the_normal_when_there_is_no_bend
        bender = create_bender
        radius = 100.0 / (Math::PI / 2.0)

        bender.sagitta = radius * (1.0 - Math.sqrt(0.5))

        assert_in_delta(90.degrees, bender.angle, 1.0e-9)
        assert_in_delta(radius, bender.radius.to_f, TOLERANCE)
        assert_in_delta(100.0, bender.arc_length.to_f, TOLERANCE)
        distance = distance_for_angle(100.0, 90.degrees)
        assert_vector(Geom::Vector3d.new(0, -distance, 0), bender.direction)
        assert(bender.concave?)
      end

      def test_set_sagitta_of_half_a_circle
        bender = create_bender

        bender.sagitta = 100.0 / Math::PI

        assert_in_delta(180.degrees, bender.angle, 1.0e-9)
      end

      # A search for the angle over the full circle, where two angles can have
      # the same sagitta, fails for the largest of these angles.
      def test_set_sagitta_gives_every_angle_up_to_the_largest_sagitta
        bender = create_bender

        (10..260).step(10) { |degrees|
          angle = degrees.degrees
          radius = 100.0 / angle

          bender.sagitta = radius * (1.0 - Math.cos(angle / 2.0))

          assert_in_delta(angle, bender.angle, 1.0e-9, "#{degrees} degrees")
        }
      end

      # The sagitta, arc length and angle are the example in the code linked
      # from issue #13.
      def test_set_sagitta_matches_a_known_angle
        instance = create_solid(BendAxes::X)
        segment = Segment.new(ORIGIN, Geom::Point3d.new(91.26921437023744, 0, 0))
        bender = Bender.new(instance, segment, Y_AXIS.reverse)

        bender.sagitta = 19.68503937007874

        assert_in_delta(1.8545904360032246, bender.angle, 1.0e-9)
      end

      def test_set_sagitta_uses_the_smaller_of_two_angles_with_the_same_sagitta
        bender = create_bender

        # Bends of about 221 and 315 degrees both have this sagitta.
        bender.sagitta = 35

        assert_in_delta(35.0, bender.sagitta.to_f, TOLERANCE)
        assert_operator(bender.angle, :>, 180.degrees)
        assert_operator(bender.angle, :<, Bender::MAX_SAGITTA_ANGLE)
      end

      def test_set_sagitta_negative_bends_away_from_the_normal
        bender = create_bender

        bender.sagitta = -100.0 / Math::PI

        assert_in_delta(180.degrees, bender.angle, 1.0e-9)
        distance = distance_for_angle(100.0, 180.degrees)
        assert_vector(Geom::Vector3d.new(0, distance, 0), bender.direction)
        assert(bender.convex?)
      end

      def test_set_sagitta_keeps_the_direction_of_the_bend
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, 2, 0))

        bender.sagitta = 10

        assert_in_delta(10.0, bender.sagitta.to_f, TOLERANCE)
        assert(bender.convex?)
      end

      def test_set_sagitta_stops_at_the_largest_sagitta
        bender = create_bender

        bender.sagitta = 50

        assert_in_delta(Bender::MAX_SAGITTA_ANGLE, bender.angle, 1.0e-9)
        assert_in_delta(bender.max_sagitta.to_f, bender.sagitta.to_f, TOLERANCE)
      end

      def test_set_sagitta_of_zero_removes_the_bend
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, -5, 0))

        bender.sagitta = 0

        refute(bender.bending?)
        assert_equal(0.0, bender.sagitta.to_f)
      end

      def test_set_sagitta_after_a_sagitta_of_zero_bends_to_the_same_side
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, 5, 0))
        bender.sagitta = 0

        bender.sagitta = 10

        assert(bender.can_bend?)
        assert_in_delta(10.0, bender.sagitta.to_f, TOLERANCE)
        assert(bender.convex?)
      end

      def test_max_sagitta_is_the_largest_sagitta_of_any_angle
        bender = create_bender
        bender.distance = 1
        max = bender.max_sagitta.to_f

        assert_in_delta(36.230567688835424, max, TOLERANCE)
        bender.angle = Bender::MAX_SAGITTA_ANGLE
        assert_in_delta(max, bender.sagitta.to_f, TOLERANCE)
        [-1.degrees, 1.degrees].each { |offset|
          bender.angle = Bender::MAX_SAGITTA_ANGLE + offset
          assert_operator(bender.sagitta.to_f, :<, max - 1.0e-4)
        }
      end

      def test_match_sagitta_keeps_the_sagitta_for_a_segment_of_another_length
        other = create_bender
        other.sagitta = -3
        bender = create_short_bender

        bender.match_sagitta(other)

        assert_in_delta(3.0, bender.sagitta.to_f, TOLERANCE)
        assert_vector(X_AXIS.reverse, bender.direction.normalize)
        assert(bender.convex?)
      end

      def test_match_sagitta_bends_towards_the_normal_like_the_other
        other = create_bender
        other.sagitta = 3
        bender = create_short_bender

        bender.match_sagitta(other)

        assert_in_delta(3.0, bender.sagitta.to_f, TOLERANCE)
        assert_vector(X_AXIS, bender.direction.normalize)
        assert(bender.concave?)
      end

      def test_match_sagitta_stops_at_the_largest_sagitta
        # This sagitta is valid for the long segment and too large for the
        # short one.
        other = create_bender
        other.sagitta = 20
        bender = create_short_bender

        bender.match_sagitta(other)

        assert_in_delta(Bender::MAX_SAGITTA_ANGLE, bender.angle, 1.0e-9)
        assert_in_delta(bender.max_sagitta.to_f, bender.sagitta.to_f, TOLERANCE)
      end

      def test_match_sagitta_keeps_an_angle_beyond_the_largest_sagitta
        other = create_bender
        other.bend(Geom::Vector3d.new(0, distance_for_angle(100.0, 300.degrees), 0))
        bender = create_bender

        bender.match_sagitta(other)

        assert_in_delta(300.degrees, bender.angle, 1.0e-9)
        assert(bender.convex?)
      end

      def test_match_sagitta_without_a_bend_resets
        bender = create_bender
        bender.bend(Geom::Vector3d.new(0, -5, 0))

        bender.match_sagitta(create_bender)

        refute(bender.bending?)
        refute(bender.can_bend?)
      end


      # The combinations of the Segmented and the Soften/Smooth option.
      BEND_OPTIONS = {
        'segmented_and_smooth' => [true, true],
        'segmented_and_hard'   => [true, false],
        'true_curve'           => [false, true],
        'true_curve_and_hard'  => [false, false],
      }.freeze

      # Bends the test solid, with a loop of edges around it that the slicing
      # planes don't pass through.
      #
      # @param [Geom::Transformation] transformation
      # @param [Boolean] towards
      # @param [Boolean] tapered
      # @param [Float] loop_at How far along the solid the loop of edges is, as
      #   a ratio of its length.
      # @yieldparam [Bender] bender Yielded before the bend is committed, for
      #   setting it up further.
      # @return [Array(Array<Array>, Sketchup::Group)] The triangles
      #   `Bender#bent_triangles` gave before the bend was committed, and the
      #   bent instance.
      def preview_and_commit(transformation, towards, tapered: true, loop_at: 0.4)
        skip('The face preview needs SketchUp 2020.') unless FaceDrawer.supported?
        axis = BendAxes::X
        instance = create_solid(axis, transformation, tapered: tapered)
        add_edge_loop(instance, axis, loop_at, tapered: tapered)
        axes = BendAxes.along(instance, axis).first
        triangles = nil
        bent = commit_bend(instance, axes, drag_vector(axes, towards)) { |bender|
          yield bender
          triangles = bender.bent_triangles(FaceColors.new(Sketchup.active_model))
        }
        [triangles, bent]
      end

      BEND_OPTIONS.each { |options, (segmented, soft_smooth)|
        [true, false].each { |towards|
          name = "test_bent_triangles_#{options}_#{towards ? 'towards' : 'away'}_" \
                 'have_the_vertices_of_the_committed_bend'
          define_method(name) {
            triangles, bent = preview_and_commit(ROTATED_SCALED_AND_MIRRORED, towards) { |bender|
              bender.segmented = segmented
              bender.soft_smooth = soft_smooth
            }

            points = triangles.flat_map(&:first)
            refute_empty(points)
            world_positions(bent).each { |vertex|
              nearest = points.map { |point| point.distance(vertex).to_f }.min
              assert_operator(nearest, :<, TOLERANCE,
                              "No triangle has a vertex at #{vertex.to_a.inspect}")
            }
          }

          name = "test_bounds_#{options}_#{towards ? 'towards' : 'away'}_contain_the_committed_bend"
          define_method(name) {
            bounds = nil
            _, bent = preview_and_commit(ROTATED_SCALED_AND_MIRRORED, towards) { |bender|
              bender.segmented = segmented
              bender.soft_smooth = soft_smooth
              bounds = bender.bounds
            }

            world_positions(bent).each { |vertex|
              assert(bounds.contains?(vertex), "The bounds don't contain #{vertex.to_a.inspect}")
            }
          }
        }
      }

      # At 300 degrees the bend reaches furthest along the reference segment a
      # fifth of the way in, where the loop of edges is. That is inside one of
      # the slices the bounds are found from, not at its corners. The solid is
      # deep enough to reach beyond the ends of the reference segment there.
      def test_bounds_contain_a_true_curve_inside_the_slices_they_are_found_from
        refute_equal(0, Bender::BOUNDS_SLICES % 5, 'The loop of edges is where two slices meet')
        deep = Geom::Transformation.scaling(1, 20, 20)
        bounds = nil
        _, bent = preview_and_commit(deep, false, tapered: false, loop_at: 0.2) { |bender|
          bender.segmented = false
          bender.angle = 300.degrees
          bounds = bender.bounds
        }

        world_positions(bent).each { |vertex|
          assert(bounds.contains?(vertex), "The bounds don't contain #{vertex.to_a.inspect}")
        }
      end

      def test_bent_triangles_cover_the_faces_of_the_committed_bend
        triangles, bent = preview_and_commit(IDENTITY, true, tapered: false) { |bender|
          bender.segmented = true
        }

        # Without a taper every face of the segmented bend is flat, so the
        # triangles cover the same area.
        expected = bent.entities.grep(Sketchup::Face).inject(0.0) { |sum, face| sum + face.area }
        area = triangles.inject(0.0) { |sum, (points, _)|
          sum + (((points[1] - points[0]) * (points[2] - points[0])).length.to_f / 2.0)
        }
        assert_in_delta(expected, area, 1.0e-3)
      end

      # The edges a segmented bend adds are hard when it is not softened, so
      # each triangle is shaded as the flat face it is part of.
      def test_bent_triangles_segmented_and_hard_has_the_normals_of_the_segments
        [true, false].each { |towards|
          triangles, = preview_and_commit(TRANSLATION * ARBITRARY_ROTATION, towards,
                                          tapered: false) { |bender|
            bender.segmented = true
            bender.soft_smooth = false
          }

          refute_empty(triangles)
          triangles.each { |points, normals, _|
            face_normal = (points[1] - points[0]) * (points[2] - points[0])
            next unless face_normal.valid?

            normals.each { |normal|
              assert_in_delta(0.0, normal.angle_between(face_normal), 1.0e-6,
                              "Bending #{towards ? 'towards' : 'away from'} the front")
            }
          }
        }
      end

      def test_bent_triangles_normals_follow_the_curve_unless_segmented_and_hard
        BEND_OPTIONS.each { |options, (segmented, soft_smooth)|
          next if segmented && !soft_smooth

          triangles, = preview_and_commit(IDENTITY, true, tapered: false) { |bender|
            bender.segmented = segmented
            bender.soft_smooth = soft_smooth
          }

          # Along the bend the direction of the curve changes within a
          # triangle.
          curved = triangles.select { |_, normals, _|
            normals[0].angle_between(normals[1]) > 1.degrees ||
              normals[0].angle_between(normals[2]) > 1.degrees
          }
          refute_empty(curved, options)
        }
      end

      def test_face_drawer_supported_from_the_version_with_vertex_normals
        refute(FaceDrawer.supported?(19))
        assert(FaceDrawer.supported?(20))
        assert(FaceDrawer.supported?(27))
      end

      def test_bent_triangles_have_the_colors_of_their_faces
        model = Sketchup.active_model
        instance = create_solid(BendAxes::X)
        instance.material = 'red'
        axes = BendAxes.along(instance, BendAxes::X).first
        bender = Bender.new(instance, axes.segment, axes.normal)
        bender.bend(drag_vector(axes, true))

        triangles = bender.bent_triangles(FaceColors.new(model, 0.5))

        refute_empty(triangles)
        triangles.each { |_, _, colors|
          assert_equal([[255, 0, 0, 127], [255, 0, 0, 127]], colors.map(&:to_a))
        }
      end

    end # class
  end # module
end # module
