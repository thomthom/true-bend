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
      TRANSLATION = Geom::Transformation.translation(Geom::Vector3d.new(30.mm, -40.mm, 50.mm))
      SCALED_AND_MIRRORED = TRANSLATION * ROTATION * Geom::Transformation.scaling(-2, 0.5, 1.5)

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

      # @param [Array<PreviewTriangle>] triangles
      # @return [Float] The area in square inches.
      def area(triangles)
        triangles.inject(0.0) { |sum, triangle|
          # The cross product of two edges has twice the area of the triangle
          # as its length.
          sum + (triangle.face_normal.length.to_f / 2.0)
        }
      end

      # @param [Array<Array(Numeric, Numeric, Numeric)>] positions Three
      #   positions, in millimetres.
      # @param [Object] color
      # @return [PreviewTriangle] A triangle with every normal pointing up.
      def horizontal_triangle(positions, color = nil)
        vertices = positions.map { |position|
          PreviewVertex.from_geom(Geom::Point3d.new(position.map(&:mm)), Z_AXIS)
        }
        PreviewTriangle.new(vertices, color, color)
      end

      # @param [Array<Numeric>] positions In millimetres.
      # @return [Array<Length>]
      def planes_at(*positions)
        positions.map(&:mm)
      end

      # @param [Sketchup::Entities] entities
      # @param [Array<Array(Numeric, Numeric, Numeric)>] corners In millimetres.
      # @return [Sketchup::Face]
      def add_face_mm(entities, *corners)
        entities.add_face(corners.map { |corner| Geom::Point3d.new(corner.map(&:mm)) })
      end

      # A group with a square face that has a square hole in it.
      #
      # @return [Sketchup::Group]
      def create_face_with_hole
        group = Sketchup.active_model.entities.add_group
        outer = add_face_mm(group.entities, [0, 0, 0], [30, 0, 0], [30, 30, 0], [0, 30, 0])
        inner = add_face_mm(group.entities, [10, 10, 0], [20, 10, 0], [20, 20, 0], [10, 20, 0])
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

        expected = (30.mm * 30.mm) - (10.mm * 10.mm)
        assert_in_delta(expected, area(triangles), TOLERANCE)
        in_hole = triangles.select { |triangle|
          a, b, c = triangle.positions
          centroid = Geom.linear_combination(0.5, a, 0.5, b)
          centroid = Geom.linear_combination(2.0 / 3.0, centroid, 1.0 / 3.0, c)
          centroid.x > 10.mm && centroid.x < 20.mm && centroid.y > 10.mm && centroid.y < 20.mm
        }
        assert_empty(in_hole)
      end

      def test_triangles_have_the_vertices_of_the_faces
        group = create_solid(BendAxes::X)
        expected = world_positions(group)

        triangles = triangulator.triangles(group)

        points = triangles.flat_map(&:positions)
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

        points = triangles.flat_map(&:positions)
        points.each { |point|
          nearest = expected.map { |candidate| candidate.distance(point).to_f }.min
          assert_operator(nearest, :<, TOLERANCE, "#{point.to_a} is not a corner of the solid")
        }
      end

      # The tapered solid has faces that are not aligned with the axes. A
      # non-uniform scaling changes the direction of the normal of such a
      # face.
      def test_triangles_normals_are_perpendicular_to_scaled_faces
        group = create_solid(BendAxes::X, SCALED_AND_MIRRORED)

        triangles = triangulator.triangles(group)

        triangles.each { |triangle|
          face_normal = triangle.face_normal
          triangle.normals.each { |normal|
            angle = normal.angle_between(face_normal)
            # Whether it points to the front is checked in another test.
            off_perpendicular = [angle, Math::PI - angle].min
            assert_in_delta(0.0, off_perpendicular, 1.0e-6)
          }
        }
      end

      def test_triangles_normals_point_to_the_front_of_mirrored_faces
        [IDENTITY, SCALED_AND_MIRRORED].each { |transformation|
          group = Sketchup.active_model.entities.add_group
          face = add_face_mm(group.entities, [0, 0, 0], [10, 0, 0], [10, 10, 5], [0, 10, 5])
          group.transformation = transformation
          on_face = face.bounds.center
          in_front = on_face.offset(face.normal, 1.mm)
          to_front = on_face.transform(transformation).vector_to(in_front.transform(transformation))

          triangles = triangulator.triangles(group)

          refute_empty(triangles)
          triangles.each { |triangle|
            triangle.normals.each { |normal|
              assert_operator(normal % to_front, :>, 0.0)
            }
          }
        }
      end

      def test_triangles_normals_are_smooth_across_soft_edges
        group = Sketchup.active_model.entities.add_group
        face1 = add_face_mm(group.entities, [0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0])
        face2 = add_face_mm(group.entities, [10, 0, 0], [20, 0, 10], [20, 10, 10], [10, 10, 0])
        [face1, face2].each { |face| face.reverse! if face.normal.z < 0 }
        shared = (face1.edges & face2.edges).first
        shared.soft = true
        shared.smooth = true

        triangles = triangulator.triangles(group)

        on_edge = triangles.flat_map(&:vertices).select { |vertex|
          (vertex.x - 10.mm).abs < TOLERANCE
        }
        assert_operator(on_edge.size, :>=, 4, 'Vertices of both faces on the shared edge')
        on_edge.each { |vertex|
          assert_in_delta(0.0, vertex.normal.angle_between(on_edge.first.normal), 1.0e-6,
                          'Both faces have the same normal on the edge')
          assert_operator(vertex.normal.angle_between(face1.normal), :>, 1.degrees)
          assert_operator(vertex.normal.angle_between(face2.normal), :>, 1.degrees)
        }
      end

      def test_triangles_include_instances_inside_the_instance
        group = Sketchup.active_model.entities.add_group
        child = create_solid(BendAxes::X, ROTATION, entities: group.entities)
        group.transformation = TRANSLATION
        expected = local_positions(child).map { |point| point.transform(TRANSLATION * ROTATION) }

        triangles = triangulator.triangles(group)

        points = triangles.flat_map(&:positions)
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
        visible = add_face_mm(group.entities, [0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0])
        add_face_mm(group.entities, [0, 0, 20], [10, 0, 20], [10, 10, 20]).hidden = true
        add_face_mm(group.entities, [0, 0, 40], [10, 0, 40], [10, 10, 40]).layer = hidden_tag
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
        face = add_face_mm(group.entities, [0, 0, 0], [10, 0, 0], [10, 10, 0], [0, 10, 0])
        face.material = 'red'
        group.material = 'blue'
        face_colors = FaceColors.new(model)

        triangles = FaceTriangulator.new(face_colors).triangles(group)

        refute_empty(triangles)
        front_color, back_color = face_colors.colors_of(face, face_colors.inherit(group))
        assert_equal([255, 0, 0, 255], front_color.to_a, 'The material of the face')
        assert_equal([0, 0, 255, 255], back_color.to_a, 'The material of the instance')
        triangles.each { |triangle|
          assert_same(front_color, triangle.front_color, 'Front')
          assert_same(back_color, triangle.back_color, 'Back')
        }
      end

      def test_slice_leaves_no_triangle_across_a_plane
        planes = planes_at(0, 25, 50, 75, 100)
        triangles = [
          horizontal_triangle([[0, 0, 0], [100, 0, 0], [0, 100, 0]]),
          horizontal_triangle([[10, 0, 30], [90, 40, 30], [60, 80, 30]]),
        ]

        sliced = triangulator.slice(triangles, planes)

        refute_empty(sliced)
        sliced.each { |triangle|
          x_min, x_max = triangle.positions.map { |position| position.x.to_f }.minmax
          between_two_planes = planes.each_cons(2).any? { |from, to|
            x_min >= from.to_f - TOLERANCE && x_max <= to.to_f + TOLERANCE
          }
          assert(between_two_planes, "A triangle spans X from #{x_min} to #{x_max}")
        }
      end

      def test_slice_keeps_the_area_and_the_winding
        planes = planes_at(0, 25, 50, 75, 100)
        triangles = [
          horizontal_triangle([[0, 0, 0], [100, 0, 0], [0, 100, 0]]),
          # This one is clockwise seen from above.
          horizontal_triangle([[10, 0, 30], [60, 80, 30], [90, 40, 30]]),
        ]

        triangles.each { |triangle|
          sliced = triangulator.slice([triangle], planes)

          assert_in_delta(area([triangle]), area(sliced), TOLERANCE)
          sliced.each { |part|
            next unless part.face_normal.valid?

            assert(part.face_normal.samedirection?(triangle.face_normal))
          }
        }
      end

      def test_slice_interpolates_normals_along_the_edges_it_splits
        vertices = [
          PreviewVertex.from_geom(Geom::Point3d.new(0.mm, 0.mm, 0.mm), X_AXIS),
          PreviewVertex.from_geom(Geom::Point3d.new(100.mm, 0.mm, 0.mm), Z_AXIS),
          PreviewVertex.from_geom(Geom::Point3d.new(0.mm, 100.mm, 0.mm), X_AXIS),
        ]
        triangle = PreviewTriangle.new(vertices, nil, nil)

        sliced = triangulator.slice([triangle], planes_at(0, 25, 100))

        on_plane = sliced.flat_map(&:vertices).select { |vertex|
          (vertex.x - 25.mm).abs < TOLERANCE
        }
        refute_empty(on_plane)
        on_plane.each { |vertex|
          assert_vector(Geom::Vector3d.new(0.75, 0, 0.25), vertex.normal)
        }
      end

      def test_slice_leaves_a_triangle_between_two_planes_as_it_is
        triangle = horizontal_triangle([[25, 0, 0], [50, 0, 0], [30, 100, 0]])

        sliced = triangulator.slice([triangle], planes_at(0, 25, 50, 75, 100))

        assert_equal(1, sliced.size)
        assert_equal(triangle.vertices, sliced.first.vertices)
      end

      # SketchUp treats lengths that are within its tolerance of each other as
      # equal.
      def test_slice_does_not_split_at_a_plane_that_only_touches_a_triangle
        triangle = horizontal_triangle([[0, 0, 0], [100, 0, 0], [0, 100, 0]])
        just_inside = 0.01.mm

        [just_inside, just_inside.to_f].each { |plane_position|
          sliced = triangulator.slice([triangle], [plane_position])

          assert_equal(1, sliced.size, "The plane position as a #{plane_position.class}")
        }
      end

      def test_slice_keeps_triangles_beyond_the_planes
        triangle = horizontal_triangle([[-50, 0, 0], [150, 0, 0], [50, 100, 0]])

        sliced = triangulator.slice([triangle], planes_at(0, 100))

        assert_in_delta(area([triangle]), area(sliced), TOLERANCE)
      end

      def test_slice_keeps_the_colors_of_each_triangle
        triangles = [
          horizontal_triangle([[0, 0, 0], [100, 0, 0], [0, 100, 0]], :lower),
          horizontal_triangle([[0, 0, 50], [100, 0, 50], [0, 100, 50]], :upper),
        ]

        sliced = triangulator.slice(triangles, planes_at(0, 50, 100))

        sliced.each { |triangle|
          expected = triangle.positions.first.z.to_f < 25.mm ? :lower : :upper
          assert_equal(expected, triangle.front_color)
          assert_equal(expected, triangle.back_color)
        }
      end

    end # class
  end # module
end # module
