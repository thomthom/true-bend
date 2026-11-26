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


      EIGHTH = QUARTER / 2.0

      # @param [Array<Array(Float, Float, Float)>] positions
      # @param [Array(Float, Float, Float)] normal The normal of every vertex.
      # @param [Object] value
      # @return [Array]
      def triangle(positions, normal = [0, 0, 1], value = nil)
        positions.map { |position| (position + normal).map(&:to_f) } + [value]
      end

      # @param [Array<Geom::Point3d>] points
      # @return [Geom::Vector3d] A vector pointing to the side the points are
      #   counter-clockwise from.
      def winding(points)
        (points[1] - points[0]) * (points[2] - points[0])
      end

      # The positions are within one 45 degree segment.
      TRIANGLE_POSITIONS = [[1, 0, 0], [EIGHTH - 1, 2, 5], [EIGHTH / 2, -3, 1]].freeze

      def test_project_triangles_puts_the_points_where_project_puts_them
        projection = PolarProjection.new(RADIUS)
        projection.axes(Geom::Point3d.new(100, 200, 300), Y_AXIS, X_AXIS)
        positions = TRIANGLE_POSITIONS.map { |position| Geom::Point3d.new(position) }
        [true, false].each { |convex|
          [nil, 45.degrees].each { |segment_angle|
            expected = projection.project(positions, convex, segment_angle)

            result = projection.project_triangles([triangle(TRIANGLE_POSITIONS)], convex,
                                                  segment_angle)

            assert_equal(1, result.size)
            assert_same_points(expected, result[0][0],
                               "Convex: #{convex}, segment angle: #{segment_angle.inspect}")
          }
        }
      end

      def test_project_triangles_segmented_puts_a_triangle_on_one_straight_segment
        source = triangle([[EIGHTH, 0, 0], [EIGHTH * 2, 0, 0], [EIGHTH * 1.5, 0, 4]])

        points, = PolarProjection.new(RADIUS).project_triangles([source], true, 45.degrees)[0]

        inset = Math.cos(22.5.degrees)
        expected = [
          polar_point(45.degrees, RADIUS),
          polar_point(90.degrees, RADIUS),
          polar_point(67.5.degrees, RADIUS * inset, 4.0),
        ]
        assert_same_points(expected, points)
      end

      def test_project_triangles_turns_normals_with_the_circle
        positions = [[QUARTER, 0, 0], [QUARTER, 0, 1], [QUARTER, 1, 0]]
        {
          # Convex, negative Y is outside the circle.
          [true, [0, -1, 0]]  => [0, 1, 0],
          [true, [1, 0, 0]]   => [-1, 0, 0],
          [true, [0, 0, 1]]   => [0, 0, 1],
          # Concave, positive Y is outside the circle.
          [false, [0, 1, 0]]  => [0, -1, 0],
          [false, [1, 0, 0]]  => [-1, 0, 0],
          [false, [0, 0, -1]] => [0, 0, -1],
        }.each { |(convex, normal), expected|
          source = triangle(positions, normal)

          _, normals, = PolarProjection.new(RADIUS).project_triangles([source], convex)[0]

          # The first position is on the circle. Away from it the normals are
          # at the same angle around the circle.
          normals.each { |projected|
            assert_vector(Geom::Vector3d.new(expected), projected,
                          "Convex: #{convex}, normal: #{normal.inspect}")
          }
        }
      end

      # Projects a small triangle with a normal that is at an angle to all
      # three axes, and asserts that the normal is still perpendicular to it.
      #
      # @param [Array(Float, Float, Float)] corner
      # @param [Boolean] convex
      # @param [Float, nil] segment_angle
      # @param [Boolean] flat
      def assert_normal_stays_perpendicular(corner, convex, segment_angle, flat)
        size = 1.0e-4
        slanted = Geom::Vector3d.new(1, 1, 0.5).normalize
        positions = [corner] + slanted.axes[0, 2].map { |along|
          Array.new(3) { |i| corner[i] + (along.to_a[i] * size) }
        }
        source = triangle(positions, slanted.to_a)
        projection = PolarProjection.new(RADIUS)

        points, normals, = projection.project_triangles([source], convex, segment_angle,
                                                        flat: flat)[0]

        # The edges are scaled up, as SketchUp treats a vector this short as
        # having no length.
        edges = [points[1] - points[0], points[2] - points[0]].map { |edge|
          Geom::Vector3d.new(edge.to_a.map { |component| component.to_f / size })
        }
        face_normal = edges[0] * edges[1]
        message = "Convex: #{convex}, corner: #{corner.inspect}"
        normals.each { |normal|
          assert_in_delta(1.0, normal.length.to_f, TOLERANCE, message)
          # The triangle is small enough to be nearly flat after the
          # projection.
          assert_in_delta(0.0, normal.angle_between(face_normal), 1.0e-3, message)
        }
      end

      # Away from the circle the projection changes lengths along the circle,
      # which turns the normal of a face that is at an angle to the circle.
      def test_project_triangles_normals_stay_perpendicular_to_slanted_faces
        [true, false].each { |convex|
          [[3.0, 5.0, 1.0], [QUARTER + 1.0, -4.0, 0.0]].each { |corner|
            assert_normal_stays_perpendicular(corner, convex, nil, false)
          }
        }
      end

      def test_project_triangles_flat_normals_stay_perpendicular_to_slanted_faces
        [true, false].each { |convex|
          [[3.0, 5.0, 1.0], [QUARTER + 1.0, -4.0, 0.0]].each { |corner|
            assert_normal_stays_perpendicular(corner, convex, 45.degrees, true)
          }
        }
      end

      # A face across a straight segment keeps its angle around the circle.
      def test_project_triangles_flat_keeps_normals_along_the_circle_at_their_own_angle
        positions = [[EIGHTH * 0.1, 0, 0], [EIGHTH * 0.9, 0, 0], [EIGHTH * 0.5, 0, 4]]
        source = triangle(positions, [1, 0, 0])

        _, normals, = PolarProjection.new(RADIUS).project_triangles([source], true, 45.degrees,
                                                                    flat: true)[0]

        angles = normals.map { |normal| normal.angle_between(X_AXIS).radians.round(3) }
        assert_equal([94.5, 112.5, 130.5], angles.sort)
      end

      def test_project_triangles_flat_turns_all_normals_in_a_segment_alike
        positions = [[EIGHTH * 0.1, 0, 0], [EIGHTH * 0.9, 0, 0], [EIGHTH * 0.5, 0, 4]]
        source = triangle(positions, [0, -1, 0])
        projection = PolarProjection.new(RADIUS)

        _, flat, = projection.project_triangles([source], true, 45.degrees, flat: true)[0]
        _, smooth, = projection.project_triangles([source], true, 45.degrees)[0]

        # The middle of the first segment is at 22.5 degrees.
        outwards = Geom::Vector3d.new(Math.cos(22.5.degrees), Math.sin(22.5.degrees), 0)
        flat.each { |normal| assert_vector(outwards, normal, 'Flat') }
        angles = smooth.map { |normal| normal.angle_between(X_AXIS).radians.round(3) }
        assert_equal([4.5, 22.5, 40.5], angles.sort, 'Not flat')
      end

      def test_project_triangles_flat_applies_only_with_a_segment_angle
        source = triangle([[EIGHTH * 0.1, 0, 0], [EIGHTH * 0.9, 0, 0], [EIGHTH * 0.5, 0, 4]],
                          [0, -1, 0])

        _, normals, = PolarProjection.new(RADIUS).project_triangles([source], true, nil,
                                                                    flat: true)[0]

        angles = normals.map { |normal| normal.angle_between(X_AXIS).radians.round(3) }
        assert_equal([4.5, 22.5, 40.5], angles.sort)
      end

      def test_project_triangles_winds_the_points_by_the_normals
        clockwise = TRIANGLE_POSITIONS.reverse
        [true, false].each { |convex|
          [TRIANGLE_POSITIONS, clockwise].each { |positions|
            [[0, 0, 1], [0, 0, -1]].each { |normal|
              source = triangle(positions, normal)

              points, normals, = PolarProjection.new(RADIUS).project_triangles([source],
                                                                               convex)[0]

              assert_operator(winding(points) % normals[0], :>, 0.0,
                              "Convex: #{convex}, normal: #{normal.inspect}")
            }
          }
        }
      end

      def test_project_triangles_keeps_each_normal_with_its_point
        up = [0.0, 0.0, 1.0]
        on_circle1 = [1.0, 0.0, 0.0] + up
        on_circle2 = [5.0, 0.0, 0.0] + up
        # This one is inside the circle, 0.3 radians around it, and its normal
        # points out of the circle.
        inside = [3.0, 2.0, 0.0, 0.0, -1.0, 0.0]
        outwards = Geom::Vector3d.new(Math.cos(0.3), Math.sin(0.3), 0)
        # The two triangles have opposite windings, so the last two points of
        # one of them are swapped to match the normal of the first.
        [[on_circle1, on_circle2, inside], [on_circle1, inside, on_circle2]].each { |vertices|
          source = vertices + [nil]

          points, normals, = PolarProjection.new(RADIUS).project_triangles([source], true)[0]

          assert_operator(winding(points) % Z_AXIS, :>, 0.0)
          points.each_with_index { |point, index|
            expected = point.distance(ORIGIN).to_f < RADIUS - 1 ? outwards : Z_AXIS
            assert_vector(expected, normals[index])
          }
        }
      end

      def test_project_triangles_passes_the_value_of_each_triangle_through
        value = Object.new
        triangles = [
          triangle(TRIANGLE_POSITIONS, [0, 0, 1], value),
          triangle(TRIANGLE_POSITIONS, [0, 0, 1], :other),
        ]

        result = PolarProjection.new(RADIUS).project_triangles(triangles, true)

        assert_same(value, result[0][2])
        assert_equal(:other, result[1][2])
      end

      def test_project_triangles_turns_normals_by_the_axes
        projection = PolarProjection.new(RADIUS)
        # Angles start at the green axis and revolve around the red axis.
        projection.axes(Geom::Point3d.new(100, 200, 300), Y_AXIS, X_AXIS)
        source = triangle([[0, 0, 0], [0, 0, 1], [0, 1, 0]], [0, -1, 0])

        _, normals, = projection.project_triangles([source], true)[0]

        normals.each { |normal| assert_vector(Y_AXIS, normal) }
      end

    end # class
  end # module
end # module
