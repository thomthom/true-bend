#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'
require_relative '../lib/test_utilities'

require 'tt_truebend/geom/polar_projection'

module TT::Plugins::TrueBend
  module Tests
    # The projection wraps the X axis around a circle in the XY plane, centred
    # on the origin: a distance along X becomes the same distance along the
    # circle, starting from where the circle crosses the X axis.
    class TC_PolarProjection < TestUp::TestCase

      include TrueBendTestUtilities

      RADIUS = 10.0
      QUARTER = Math::PI * RADIUS / 2.0 # A quarter of the circumference.

      def setup
        # ...
      end

      def teardown
        # ...
      end


      # @param [Float] angle In radians.
      # @param [Float] radius
      # @param [Float] z
      # @return [Geom::Point3d]
      def polar_point(angle, radius, z = 0.0)
        Geom::Point3d.new(radius * Math.cos(angle), radius * Math.sin(angle), z)
      end

      # @param [Boolean] convex
      # @param [Array<Array(Float, Float, Float)>] points
      # @return [Array<Geom::Point3d>]
      def project(convex, *points, segment_angle: nil)
        projection = PolarProjection.new(RADIUS)
        projection.project(points.map { |point| Geom::Point3d.new(point) }, convex, segment_angle)
      end


      def test_project_convex_wraps_counter_clockwise
        result = project(true, [0, 0, 0], [QUARTER, 0, 0], [QUARTER * 2, 0, 0], [-QUARTER, 0, 0])

        assert_point(Geom::Point3d.new(RADIUS, 0, 0), result[0])
        assert_point(Geom::Point3d.new(0, RADIUS, 0), result[1])
        assert_point(Geom::Point3d.new(-RADIUS, 0, 0), result[2])
        assert_point(Geom::Point3d.new(0, -RADIUS, 0), result[3])
      end

      def test_project_concave_wraps_clockwise
        result = project(false, [0, 0, 0], [QUARTER, 0, 0], [QUARTER * 2, 0, 0], [-QUARTER, 0, 0])

        assert_point(Geom::Point3d.new(RADIUS, 0, 0), result[0])
        assert_point(Geom::Point3d.new(0, -RADIUS, 0), result[1])
        assert_point(Geom::Point3d.new(-RADIUS, 0, 0), result[2])
        assert_point(Geom::Point3d.new(0, RADIUS, 0), result[3])
      end

      def test_project_convex_positive_y_is_inside_the_circle
        result = project(true, [0, 2, 0], [QUARTER, 2, 0], [QUARTER, -3, 0])

        assert_point(Geom::Point3d.new(RADIUS - 2, 0, 0), result[0])
        assert_point(Geom::Point3d.new(0, RADIUS - 2, 0), result[1])
        assert_point(Geom::Point3d.new(0, RADIUS + 3, 0), result[2])
      end

      def test_project_concave_positive_y_is_outside_the_circle
        result = project(false, [0, 2, 0], [QUARTER, 2, 0], [QUARTER, -3, 0])

        assert_point(Geom::Point3d.new(RADIUS + 2, 0, 0), result[0])
        assert_point(Geom::Point3d.new(0, -(RADIUS + 2), 0), result[1])
        assert_point(Geom::Point3d.new(0, -(RADIUS - 3), 0), result[2])
      end

      def test_project_keeps_z
        [true, false].each { |convex|
          result = project(convex, [0, 0, 7], [QUARTER, 2, -4])

          assert_in_delta(7.0, result[0].z.to_f, TOLERANCE, "Convex: #{convex}")
          assert_in_delta(-4.0, result[1].z.to_f, TOLERANCE, "Convex: #{convex}")
        }
      end

      def test_project_keeps_distances_along_the_x_axis
        result = project(true, [3, 0, 0], [3, 2, 0])

        assert_point(polar_point(3 / RADIUS, RADIUS), result[0])
        # Inside the circle the same angle spans a shorter distance.
        assert_point(polar_point(3 / RADIUS, RADIUS - 2), result[1])
      end

      # With a segment angle the circle is made of straight segments, each
      # spanning that angle. Points keep their angle around the circle, and end
      # up on the segment instead of on the circle.
      def test_project_segmented_puts_points_on_straight_segments
        segment_angle = 45.degrees
        eighth = QUARTER / 2.0
        # Halfway along a segment, the segment is this much closer to the
        # centre than the circle is.
        inset = Math.cos(segment_angle / 2.0)
        result = project(true, [0, 0, 0], [eighth / 2, 0, 0], [eighth, 0, 0],
                         [eighth * 1.5, 2, 5], segment_angle: segment_angle)

        assert_point(polar_point(0.0, RADIUS), result[0], 'Start of a segment')
        assert_point(polar_point(22.5.degrees, RADIUS * inset), result[1], 'Middle of a segment')
        assert_point(polar_point(45.degrees, RADIUS), result[2], 'Between two segments')
        assert_point(polar_point(67.5.degrees, (RADIUS - 2) * inset, 5.0), result[3],
                     'Middle of the next segment, inside the circle')
      end

      def test_project_segmented_concave
        segment_angle = 45.degrees
        eighth = QUARTER / 2.0
        inset = Math.cos(segment_angle / 2.0)
        result = project(false, [eighth / 2, 0, 0], [eighth, 0, 0], [eighth * 1.5, 2, 5],
                         segment_angle: segment_angle)

        assert_point(polar_point(-22.5.degrees, RADIUS * inset), result[0], 'Middle of a segment')
        assert_point(polar_point(-45.degrees, RADIUS), result[1], 'Between two segments')
        assert_point(polar_point(-67.5.degrees, (RADIUS + 2) * inset, 5.0), result[2],
                     'Middle of the next segment, outside the circle')
      end

      def test_axes_places_the_circle
        origin = Geom::Point3d.new(100, 200, 300)
        projection = PolarProjection.new(RADIUS)
        projection.axes(origin, Y_AXIS, X_AXIS)
        points = [Geom::Point3d.new(0, 0, 0), Geom::Point3d.new(QUARTER, 0, 4)]

        result = projection.project(points, true)

        # Angles start at the green axis and revolve around the red axis, so a
        # quarter of a circle on from green is blue.
        assert_point(Geom::Point3d.new(100, 200 + RADIUS, 300), result[0])
        assert_point(Geom::Point3d.new(104, 200, 300 + RADIUS), result[1])
      end

      def test_project_does_not_modify_the_points
        point = Geom::Point3d.new(QUARTER, 2, 3)
        projection = PolarProjection.new(RADIUS)
        projection.axes(Geom::Point3d.new(1, 2, 3), X_AXIS, Z_AXIS)

        projection.project([point], true, 45.degrees)

        assert_point(Geom::Point3d.new(QUARTER, 2, 3), point)
      end

    end # class
  end # module
end # module
