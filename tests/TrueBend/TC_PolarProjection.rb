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
      # @return [PreviewTriangle]
      def triangle(positions, normal = [0, 0, 1])
        vertices = positions.map { |position|
          PreviewVertex.from_geom(Geom::Point3d.new(position), Geom::Vector3d.new(normal))
        }
        PreviewTriangle.new(vertices, :front_color, :back_color)
      end

      # @param [PreviewTriangle] triangle
      # @param [Boolean] convex
      # @param [Float, nil] segment_angle
      # @param [Boolean] smooth
      # @return [PreviewTriangle]
      def project_triangle(triangle, convex, segment_angle = nil, smooth: true)
        projection = PolarProjection.new(RADIUS)
        projected = projection.project_triangles([triangle], convex, segment_angle, smooth: smooth)
        assert_equal(1, projected.size)
        projected.first
      end

      # @param [Array<Geom::Vector3d>] normals
      # @return [Array<Float>] The angle between each normal and the X axis,
      #   in degrees, in ascending order.
      def sorted_angles_to_x_axis(normals)
        normals.map { |normal| normal.angle_between(X_AXIS).radians.round(3) }.sort
      end

      # The positions are within one 45 degree segment.
      TRIANGLE_POSITIONS = [[1, 0, 0], [EIGHTH - 1, 2, 5], [EIGHTH / 2, -3, 1]].freeze

      # A triangle that spans most of the first 45 degree segment, on the
      # circle.
      SEGMENT_POSITIONS = [[EIGHTH * 0.1, 0, 0], [EIGHTH * 0.9, 0, 0], [EIGHTH * 0.5, 0, 4]].freeze

      def test_project_triangles_puts_the_vertices_where_project_puts_points
        projection = PolarProjection.new(RADIUS)
        projection.axes(Geom::Point3d.new(100, 200, 300), Y_AXIS, X_AXIS)
        points = TRIANGLE_POSITIONS.map { |position| Geom::Point3d.new(position) }
        [true, false].each { |convex|
          [nil, 45.degrees].each { |segment_angle|
            expected = projection.project(points, convex, segment_angle)

            projected = projection.project_triangles([triangle(TRIANGLE_POSITIONS)], convex,
                                                     segment_angle)

            assert_equal(1, projected.size)
            assert_same_points(expected, projected.first.positions,
                               "Convex: #{convex}, segment angle: #{segment_angle.inspect}")
          }
        }
      end

      def test_project_triangles_segmented_puts_a_triangle_on_one_straight_segment
        source = triangle([[EIGHTH, 0, 0], [EIGHTH * 2, 0, 0], [EIGHTH * 1.5, 0, 4]])

        projected = project_triangle(source, true, 45.degrees)

        chord_distance = RADIUS * Math.cos(22.5.degrees)
        expected = [
          polar_point(45.degrees, RADIUS),
          polar_point(90.degrees, RADIUS),
          polar_point(67.5.degrees, chord_distance, 4.0),
        ]
        assert_same_points(expected, projected.positions)
      end

      def test_project_triangles_rotates_normals_with_the_circle
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
          projected = project_triangle(triangle(positions, normal), convex)

          # The first position is on the circle. The other two are at the same
          # angle around it.
          projected.normals.each { |projected_normal|
            assert_vector(Geom::Vector3d.new(expected), projected_normal,
                          "Convex: #{convex}, normal: #{normal.inspect}")
          }
        }
      end

      # Projects a small triangle whose normal is at an angle to all three
      # axes, and asserts that the normal is still perpendicular to it.
      #
      # @param [Array(Float, Float, Float)] corner
      # @param [Boolean] convex
      # @param [Float, nil] segment_angle
      # @param [Boolean] smooth
      def assert_normal_stays_perpendicular(corner, convex, segment_angle, smooth)
        size = 1.0e-4
        slanted_normal = Geom::Vector3d.new(1, 1, 0.5).normalize
        positions = [corner] + slanted_normal.axes[0, 2].map { |edge_direction|
          Array.new(3) { |i| corner[i] + (edge_direction.to_a[i] * size) }
        }
        source = triangle(positions, slanted_normal.to_a)

        projected = project_triangle(source, convex, segment_angle, smooth: smooth)

        # SketchUp treats a vector as short as these edges as having no
        # length, so the edges are scaled up.
        a, b, c = projected.positions
        edges = [b - a, c - a].map { |edge|
          Geom::Vector3d.new(edge.to_a.map { |component| component.to_f / size })
        }
        face_normal = edges[0] * edges[1]
        message = "Convex: #{convex}, corner: #{corner.inspect}"
        projected.normals.each { |normal|
          assert_in_delta(1.0, normal.length.to_f, TOLERANCE, message)
          # The triangle is small enough to be nearly flat after the
          # projection.
          assert_in_delta(0.0, normal.angle_between(face_normal), 1.0e-3, message)
        }
      end

      # Away from the circle the projection scales lengths along the circle,
      # which changes the direction of a normal that is at an angle to the
      # circle.
      def test_project_triangles_normals_stay_perpendicular_to_slanted_faces
        [true, false].each { |convex|
          [[3.0, 5.0, 1.0], [QUARTER + 1.0, -4.0, 0.0]].each { |corner|
            assert_normal_stays_perpendicular(corner, convex, nil, true)
          }
        }
      end

      def test_project_triangles_not_smooth_normals_stay_perpendicular_to_slanted_faces
        [true, false].each { |convex|
          [[3.0, 5.0, 1.0], [QUARTER + 1.0, -4.0, 0.0]].each { |corner|
            assert_normal_stays_perpendicular(corner, convex, 45.degrees, false)
          }
        }
      end

      # A face across a straight segment stays on a line through the origin.
      def test_project_triangles_not_smooth_keeps_a_tangential_normal_at_the_angle_of_its_vertex
        source = triangle(SEGMENT_POSITIONS, [1, 0, 0])

        projected = project_triangle(source, true, 45.degrees, smooth: false)

        assert_equal([94.5, 112.5, 130.5], sorted_angles_to_x_axis(projected.normals))
      end

      def test_project_triangles_not_smooth_gives_radial_normals_the_direction_of_the_segment
        source = triangle(SEGMENT_POSITIONS, [0, -1, 0])

        not_smooth = project_triangle(source, true, 45.degrees, smooth: false)
        smooth = project_triangle(source, true, 45.degrees)

        # The middle of the first segment is at 22.5 degrees.
        segment_normal = Geom::Vector3d.new(Math.cos(22.5.degrees), Math.sin(22.5.degrees), 0)
        not_smooth.normals.each { |normal| assert_vector(segment_normal, normal, 'Not smooth') }
        assert_equal([4.5, 22.5, 40.5], sorted_angles_to_x_axis(smooth.normals), 'Smooth')
      end

      def test_project_triangles_is_always_smooth_without_a_segment_angle
        source = triangle(SEGMENT_POSITIONS, [0, -1, 0])

        projected = project_triangle(source, true, nil, smooth: false)

        assert_equal([4.5, 22.5, 40.5], sorted_angles_to_x_axis(projected.normals))
      end

      # Two triangles on different segments can share a vertex where the
      # segments meet.
      def test_project_triangles_not_smooth_projects_a_shared_vertex_for_each_segment
        radial_vertex = lambda { |x, z|
          PreviewVertex.from_geom(Geom::Point3d.new(x, 0, z), Geom::Vector3d.new(0, -1, 0))
        }
        shared = radial_vertex.call(EIGHTH, 0)
        triangles = [
          [radial_vertex.call(EIGHTH * 0.2, 0), shared, radial_vertex.call(EIGHTH * 0.6, 4)],
          [shared, radial_vertex.call(EIGHTH * 1.8, 0), radial_vertex.call(EIGHTH * 1.4, 4)],
        ].map { |vertices| PreviewTriangle.new(vertices, :front_color, :back_color) }

        projected = PolarProjection.new(RADIUS).project_triangles(triangles, true, 45.degrees,
                                                                  smooth: false)

        [22.5.degrees, 67.5.degrees].each_with_index { |mid_angle, index|
          segment_normal = Geom::Vector3d.new(Math.cos(mid_angle), Math.sin(mid_angle), 0)
          projected[index].normals.each { |normal|
            assert_vector(segment_normal, normal, "Segment #{index}")
          }
        }
      end

      def test_project_triangles_orders_the_vertices_counter_clockwise_seen_from_their_normals
        clockwise = TRIANGLE_POSITIONS.reverse
        [true, false].each { |convex|
          [TRIANGLE_POSITIONS, clockwise].each { |positions|
            [[0, 0, 1], [0, 0, -1]].each { |normal|
              projected = project_triangle(triangle(positions, normal), convex)

              assert_operator(projected.face_normal % projected.normals.first, :>, 0.0,
                              "Convex: #{convex}, normal: #{normal.inspect}")
            }
          }
        }
      end

      def test_project_triangles_keeps_each_normal_with_its_position
        on_circle1 = PreviewVertex.from_geom(Geom::Point3d.new(1, 0, 0), Z_AXIS)
        on_circle2 = PreviewVertex.from_geom(Geom::Point3d.new(5, 0, 0), Z_AXIS)
        # This one is inside the circle, 0.3 radians around it, and its normal
        # points out of the circle.
        inside = PreviewVertex.from_geom(Geom::Point3d.new(3, 2, 0), Geom::Vector3d.new(0, -1, 0))
        radial = Geom::Vector3d.new(Math.cos(0.3), Math.sin(0.3), 0)
        # The two triangles have opposite windings, so the vertices of one of
        # them are reordered.
        [[on_circle1, on_circle2, inside], [on_circle1, inside, on_circle2]].each { |vertices|
          source = PreviewTriangle.new(vertices, :front_color, :back_color)

          projected = project_triangle(source, true)

          assert_operator(projected.face_normal % Z_AXIS, :>, 0.0)
          projected.vertices.each { |vertex|
            expected = vertex.position.distance(ORIGIN).to_f < RADIUS - 1 ? radial : Z_AXIS
            assert_vector(expected, vertex.normal)
          }
        }
      end

      def test_project_triangles_keeps_the_colors_of_each_triangle
        front_color = Sketchup::Color.new('red')
        back_color = Sketchup::Color.new('blue')
        vertices = triangle(TRIANGLE_POSITIONS).vertices
        triangles = [
          PreviewTriangle.new(vertices, front_color, back_color),
          triangle(TRIANGLE_POSITIONS),
        ]

        projected = PolarProjection.new(RADIUS).project_triangles(triangles, true)

        assert_same(front_color, projected[0].front_color)
        assert_same(back_color, projected[0].back_color)
        assert_equal(:front_color, projected[1].front_color)
        assert_equal(:back_color, projected[1].back_color)
      end

      def test_project_triangles_transforms_normals_by_the_axes
        projection = PolarProjection.new(RADIUS)
        # Angles start at the green axis and revolve around the red axis.
        projection.axes(Geom::Point3d.new(100, 200, 300), Y_AXIS, X_AXIS)
        source = triangle([[0, 0, 0], [0, 0, 1], [0, 1, 0]], [0, -1, 0])

        projected = projection.project_triangles([source], true).first

        projected.normals.each { |normal| assert_vector(Y_AXIS, normal) }
      end

    end # class
  end # module
end # module
