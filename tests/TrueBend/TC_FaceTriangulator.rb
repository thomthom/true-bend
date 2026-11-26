#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'
require_relative '../lib/test_utilities'

require 'tt_truebend/gl/face_colors'
require 'tt_truebend/gl/face_drawer'
require 'tt_truebend/gl/face_triangulator'

module TT::Plugins::TrueBend
  module Tests
    class TC_FaceTriangulator < TestUp::TestCase

      include TrueBendTestUtilities

      ROTATION = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 2, 3), 37.degrees)
      TRANSLATION = Geom::Transformation.translation(Geom::Vector3d.new(30, -40, 50))
      SCALED_AND_MIRRORED = TRANSLATION * ROTATION * Geom::Transformation.scaling(-2, 0.5, 1.5)

      UP = [0.0, 0.0, 1.0].freeze

      def setup
        skip('The face preview needs SketchUp 2020.') unless FaceDrawer.supported?
        start_with_empty_model
      end

      def teardown
        # ...
      end


      # @return [FaceTriangulator]
      def triangulator
        FaceTriangulator.new(FaceColors.new(Sketchup.active_model))
      end

      # @param [Array<Float>] vertex
      # @return [Geom::Point3d]
      def position(vertex)
        Geom::Point3d.new(vertex[0, 3])
      end

      # @param [Array<Float>] vertex
      # @return [Geom::Vector3d]
      def normal(vertex)
        Geom::Vector3d.new(vertex[3, 3])
      end

      # @param [Array] triangle
      # @return [Geom::Vector3d] A vector perpendicular to the triangle, with
      #   twice the area of the triangle as its length. It points to the side
      #   the vertices are counter-clockwise from.
      def cross(triangle)
        a, b, c = triangle[0, 3].map { |vertex| position(vertex) }
        (b - a) * (c - a)
      end

      # @param [Array<Array>] triangles
      # @return [Float]
      def area(triangles)
        triangles.inject(0.0) { |sum, triangle| sum + (cross(triangle).length.to_f / 2.0) }
      end

      # @param [Array<Array>] coordinates Three positions.
      # @param [Object] colors
      # @return [Array] A triangle with every normal pointing up.
      def flat_triangle(coordinates, colors = nil)
        coordinates.map { |xyz| xyz.map(&:to_f) + UP } + [colors]
      end

      # A group with a square face that has a square hole in it.
      #
      # @return [Sketchup::Group]
      def create_face_with_hole
        group = Sketchup.active_model.entities.add_group
        outer = group.entities.add_face([0, 0, 0], [30, 0, 0], [30, 30, 0], [0, 30, 0])
        inner = group.entities.add_face([10, 10, 0], [20, 10, 0], [20, 20, 0], [10, 20, 0])
        inner.erase!
        assert_equal(2, outer.loops.size, 'The face should have a hole')
        group
      end


      def test_triangles_cover_the_faces
        group = create_solid(BendAxes::X)
        expected = group.entities.grep(Sketchup::Face).inject(0.0) { |sum, face| sum + face.area }

        triangles = triangulator.triangles(group)

        assert_in_delta(expected, area(triangles), TOLERANCE)
      end

      def test_triangles_leave_holes_open
        group = create_face_with_hole

        triangles = triangulator.triangles(group)

        assert_in_delta(800.0, area(triangles), TOLERANCE)
        in_hole = triangles.select { |triangle|
          centroid = Geom.linear_combination(0.5, position(triangle[0]), 0.5, position(triangle[1]))
          centroid = Geom.linear_combination(2.0 / 3.0, centroid, 1.0 / 3.0, position(triangle[2]))
          centroid.x > 10 && centroid.x < 20 && centroid.y > 10 && centroid.y < 20
        }
        assert_empty(in_hole)
      end

      def test_triangles_have_the_vertices_of_the_faces
        group = create_solid(BendAxes::X)
        expected = world_positions(group)

        triangles = triangulator.triangles(group)

        points = triangles.flat_map { |triangle| triangle[0, 3].map { |v| position(v) } }
        expected.each { |point|
          nearest = points.map { |candidate| candidate.distance(point).to_f }.min
          assert_operator(nearest, :<, TOLERANCE, "No triangle has a vertex at #{point.to_a}")
        }
      end

      def test_triangles_are_placed_by_the_instance_and_the_given_transformation
        group = create_solid(BendAxes::X, SCALED_AND_MIRRORED)
        to_target = ROTATION.inverse
        expected = world_positions(group).map { |point| point.transform(to_target) }

        triangles = triangulator.triangles(group, to_target)

        points = triangles.flat_map { |triangle| triangle[0, 3].map { |v| position(v) } }
        points.each { |point|
          nearest = expected.map { |candidate| candidate.distance(point).to_f }.min
          assert_operator(nearest, :<, TOLERANCE, "#{point.to_a} is not a corner of the solid")
        }
      end

      # The tapered solid has faces that are not aligned with the axes, and
      # the normal of such a face is turned by a non-uniform scaling.
      def test_triangles_normals_are_perpendicular_to_scaled_faces
        group = create_solid(BendAxes::X, SCALED_AND_MIRRORED)

        triangles = triangulator.triangles(group)

        triangles.each { |triangle|
          face_normal = cross(triangle).normalize
          triangle[0, 3].each { |vertex|
            angle = normal(vertex).angle_between(face_normal)
            # Whether it points to the front is checked in another test.
            off_perpendicular = [angle, Math::PI - angle].min
            assert_in_delta(0.0, off_perpendicular, 1.0e-6)
          }
        }
      end

      def test_triangles_normals_point_to_the_front_of_mirrored_faces
        [IDENTITY, SCALED_AND_MIRRORED].each { |transformation|
          group = Sketchup.active_model.entities.add_group
          face = group.entities.add_face([0, 0, 0], [10, 0, 0], [10, 10, 5], [0, 10, 5])
          group.transformation = transformation
          on_face = face.bounds.center
          in_front = on_face.offset(face.normal, 1.0)
          to_front = on_face.transform(transformation).vector_to(in_front.transform(transformation))

          triangles = triangulator.triangles(group)

          refute_empty(triangles)
          triangles.each { |triangle|
            triangle[0, 3].each { |vertex|
              assert_operator(normal(vertex) % to_front, :>, 0.0)
            }
          }
        }
      end

      def test_triangles_normals_are_smooth_across_soft_edges
        group = Sketchup.active_model.entities.add_group
        face1 = group.entities.add_face([0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0])
        face2 = group.entities.add_face([10, 0, 0], [20, 0, 10], [20, 10, 10], [10, 10, 0])
        [face1, face2].each { |face| face.reverse! if face.normal.z < 0 }
        shared = (face1.edges & face2.edges).first
        shared.soft = true
        shared.smooth = true

        triangles = triangulator.triangles(group)

        on_edge = triangles.flat_map { |triangle| triangle[0, 3] }.select { |vertex|
          (vertex[0] - 10.0).abs < TOLERANCE
        }
        assert_operator(on_edge.size, :>=, 4, 'Vertices of both faces on the shared edge')
        on_edge.each { |vertex|
          assert_in_delta(0.0, normal(vertex).angle_between(normal(on_edge.first)), 1.0e-6,
                          'Both faces have the same normal on the edge')
          assert_operator(normal(vertex).angle_between(face1.normal), :>, 1.degrees)
          assert_operator(normal(vertex).angle_between(face2.normal), :>, 1.degrees)
        }
      end

      def test_triangles_include_instances_inside_the_instance
        group = Sketchup.active_model.entities.add_group
        child = create_solid(BendAxes::X, ROTATION, entities: group.entities)
        group.transformation = TRANSLATION
        expected = local_positions(child).map { |point| point.transform(TRANSLATION * ROTATION) }

        triangles = triangulator.triangles(group)

        points = triangles.flat_map { |triangle| triangle[0, 3].map { |v| position(v) } }
        refute_empty(points)
        points.each { |point|
          nearest = expected.map { |candidate| candidate.distance(point).to_f }.min
          assert_operator(nearest, :<, TOLERANCE, "#{point.to_a} is not a corner of the solid")
        }
      end

      def test_triangles_skip_what_is_hidden
        model = Sketchup.active_model
        hidden_tag = model.layers.add('Hidden')
        hidden_tag.visible = false
        group = model.entities.add_group
        visible = group.entities.add_face([0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0])
        group.entities.add_face([0, 0, 20], [10, 0, 20], [10, 10, 20]).hidden = true
        group.entities.add_face([0, 0, 40], [10, 0, 40], [10, 10, 40]).layer = hidden_tag
        create_solid(BendAxes::X, entities: group.entities).hidden = true
        create_solid(BendAxes::Y, entities: group.entities).layer = hidden_tag
        hidden_parent = group.entities.add_group
        create_solid(BendAxes::X, entities: hidden_parent.entities)
        hidden_parent.hidden = true

        triangles = triangulator.triangles(group)

        assert_in_delta(visible.area, area(triangles), TOLERANCE)
      end

      # @param [Sketchup::Entities] entities
      # @param [Length] z
      # @return [Sketchup::Face] A square face.
      def add_square(entities, z = 0.mm)
        size = 10.mm
        entities.add_face([0, 0, z], [size, 0, z], [size, size, z], [0, size, z])
      end

      # A tag can be visible while a folder it is in is hidden.
      def test_triangles_skip_what_a_hidden_tag_folder_hides
        model = Sketchup.active_model
        skip('Needs tag folders.') unless model.layers.respond_to?(:add_folder)
        tag = model.layers.add('In Folder')
        folder = model.layers.add_folder('Hidden')
        folder.add_layer(tag)
        folder.visible = false
        group = model.entities.add_group
        visible = add_square(group.entities)
        add_square(group.entities, 20.mm).layer = tag
        create_solid(BendAxes::X, entities: group.entities).layer = tag

        triangles = triangulator.triangles(group)

        assert(tag.visible?, 'The tag itself is visible')
        assert_in_delta(visible.area, area(triangles), TOLERANCE)
      end

      def test_triangles_include_hidden_faces_when_the_view_shows_hidden_geometry
        model = Sketchup.active_model
        options = model.rendering_options
        option = 'DrawHiddenGeometry'
        skip("Needs the \"#{option}\" option.") unless options.keys.include?(option)
        group = model.entities.add_group
        visible = add_square(group.entities)
        hidden = add_square(group.entities, 20.mm)
        hidden.hidden = true
        shown = options[option]
        options[option] = true

        triangles = triangulator.triangles(group)

        assert_in_delta(visible.area + hidden.area, area(triangles), TOLERANCE)
      ensure
        options[option] = shown unless shown.nil?
      end

      def test_triangles_have_the_colors_of_their_face
        model = Sketchup.active_model
        group = model.entities.add_group
        face = group.entities.add_face([0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0])
        face.material = 'red'
        group.material = 'blue'
        colors = FaceColors.new(model)

        triangles = FaceTriangulator.new(colors).triangles(group)

        refute_empty(triangles)
        expected = colors.colors(face, colors.inherit(group))
        assert_equal([255, 0, 0, 255], expected[0].to_a, 'The material of the face')
        assert_equal([0, 0, 255, 255], expected[1].to_a, 'The material of the instance')
        triangles.each { |triangle|
          assert_same(expected[0], triangle[3][0], 'Front')
          assert_same(expected[1], triangle[3][1], 'Back')
        }
      end

      def test_slice_leaves_no_triangle_across_a_cut
        cuts = [0.0, 2.5, 5.0, 7.5, 10.0]
        triangles = [
          flat_triangle([[0, 0, 0], [10, 0, 0], [0, 10, 0]]),
          flat_triangle([[1, 0, 3], [9, 4, 3], [6, 8, 3]]),
        ]

        result = triangulator.slice(triangles, cuts)

        refute_empty(result)
        result.each { |triangle|
          min, max = triangle[0, 3].map(&:first).minmax
          between = cuts.each_cons(2).any? { |from, to|
            min >= from - TOLERANCE && max <= to + TOLERANCE
          }
          assert(between, "A triangle spans X from #{min} to #{max}")
        }
      end

      def test_slice_keeps_the_area_and_the_winding
        cuts = [0.0, 2.5, 5.0, 7.5, 10.0]
        triangles = [
          flat_triangle([[0, 0, 0], [10, 0, 0], [0, 10, 0]]),
          # This one is clockwise seen from above.
          flat_triangle([[1, 0, 3], [6, 8, 3], [9, 4, 3]]),
        ]

        triangles.each { |triangle|
          result = triangulator.slice([triangle], cuts)

          assert_in_delta(area([triangle]), area(result), TOLERANCE)
          result.each { |part|
            next unless cross(part).valid?

            assert(cross(part).samedirection?(cross(triangle)))
          }
        }
      end

      def test_slice_interpolates_normals_along_the_cut_edges
        triangle = [
          [0.0, 0.0, 0.0, 1.0, 0.0, 0.0],
          [10.0, 0.0, 0.0, 0.0, 0.0, 1.0],
          [0.0, 10.0, 0.0, 1.0, 0.0, 0.0],
          nil,
        ]

        result = triangulator.slice([triangle], [0.0, 2.5, 10.0])

        on_cut = result.flat_map { |part| part[0, 3] }.select { |vertex|
          (vertex[0] - 2.5).abs < TOLERANCE
        }
        refute_empty(on_cut)
        on_cut.each { |vertex|
          assert_in_delta(0.75, vertex[3], TOLERANCE, 'X of the normal')
          assert_in_delta(0.0, vertex[4], TOLERANCE, 'Y of the normal')
          assert_in_delta(0.25, vertex[5], TOLERANCE, 'Z of the normal')
        }
      end

      def test_slice_leaves_a_triangle_between_two_cuts_as_it_is
        triangle = flat_triangle([[2.5, 0, 0], [5, 0, 0], [3, 10, 0]])

        result = triangulator.slice([triangle], [0.0, 2.5, 5.0, 7.5, 10.0])

        assert_equal([triangle], result)
      end

      def test_slice_keeps_triangles_beyond_the_cuts
        triangle = flat_triangle([[-5, 0, 0], [15, 0, 0], [5, 10, 0]])

        result = triangulator.slice([triangle], [0.0, 10.0])

        assert_in_delta(area([triangle]), area(result), TOLERANCE)
      end

      def test_slice_keeps_the_colors_of_each_triangle
        triangles = [
          flat_triangle([[0, 0, 0], [10, 0, 0], [0, 10, 0]], :first),
          flat_triangle([[0, 0, 5], [10, 0, 5], [0, 10, 5]], :second),
        ]

        result = triangulator.slice(triangles, [0.0, 5.0, 10.0])

        result.each { |triangle|
          expected = triangle[0][2] == 0.0 ? :first : :second
          assert_equal(expected, triangle[3])
        }
      end

    end # class
  end # module
end # module
