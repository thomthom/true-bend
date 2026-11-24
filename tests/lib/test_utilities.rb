#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'tt_truebend/bender'
require 'tt_truebend/tools/truebend'

module TT::Plugins::TrueBend
  module Tests
    # Builds instances to bend, and works out where a true circular bend puts
    # their vertices without using any of the extension's own maths.
    module TrueBendTestUtilities

      # Positions are compared by their distance as a `Float`. `Length` and
      # `Geom::Point3d` comparisons have SketchUp's 0.001" tolerance built in,
      # which is too coarse to tell a correct bend from a nearly correct one.
      TOLERANCE = 1.0e-6

      # The axes of an instance, as indices into a point. An instance is bent
      # along its red axis.
      X = 0
      Y = 1
      Z = 2

      # How a bend is set up: the reference segment that the instance is bent
      # along, and the direction it is bent in.
      BendSetup = Struct.new(:segment, :normal)

      # The test solid is long in one direction, to bend along, and thin in the
      # other two. It is thinner than the radius of the bends made in the
      # tests, as a solid that reaches past the centre of a bend is turned
      # inside out by it.
      #
      # It deliberately keeps clear of the instance origin: the reference
      # segment of a bend runs through the origin, not along the solid.
      SOLID_START = -20.0
      SOLID_END = 80.0
      # The cross sections at each end, as the lower and upper corner in the
      # two directions across. The solid tapers, which makes its two ends
      # different, so a bend that came out reversed is noticed.
      SOLID_START_SECTION = [[4.0, -9.0], [12.0, -3.0]].freeze
      SOLID_END_SECTION = [[6.0, -8.0], [11.0, -5.0]].freeze

      # The number of segments the tests bend the instances with.
      SUBDIVISIONS = 6

      # How far the bend handle is dragged, as a ratio of the length of the
      # reference segment. This gives a bend of about 94 degrees.
      DRAG_RATIO = 1.0 / 12.0

      # @param [Integer] axis The axis the point is `along` on.
      # @param [Float] along
      # @param [Float] across1 Coordinate on the next axis, in X, Y, Z order.
      # @param [Float] across2 Coordinate on the axis after that.
      # @return [Geom::Point3d]
      def point_along(axis, along, across1, across2)
        coordinates = [0.0, 0.0, 0.0]
        coordinates[axis] = along
        coordinates[(axis + 1) % 3] = across1
        coordinates[(axis + 2) % 3] = across2
        Geom::Point3d.new(coordinates)
      end

      # The corners of the test solid, in instance coordinates. The first four
      # are around its start, the last four around its end, in the same order.
      #
      # @param [Integer] axis The axis the solid is long in.
      # @param [Boolean] tapered
      # @return [Array<Geom::Point3d>]
      def solid_corners(axis, tapered: true)
        end_section = tapered ? SOLID_END_SECTION : SOLID_START_SECTION
        ends = [[SOLID_START, SOLID_START_SECTION], [SOLID_END, end_section]]
        ends.flat_map { |along, (lower, upper)|
          [
            point_along(axis, along, lower[0], lower[1]),
            point_along(axis, along, upper[0], lower[1]),
            point_along(axis, along, upper[0], upper[1]),
            point_along(axis, along, lower[0], upper[1]),
          ]
        }
      end

      # Points at the given position along each of the four long edges of the
      # test solid, in instance coordinates.
      #
      # @param [Integer] axis
      # @param [Float] ratio 0.0 is the start of the solid and 1.0 the end.
      # @param [Boolean] tapered
      # @return [Array<Geom::Point3d>]
      def solid_section(axis, ratio, tapered: true)
        corners = solid_corners(axis, tapered: tapered)
        Array.new(4) { |i|
          Geom.linear_combination(1.0 - ratio, corners[i], ratio, corners[i + 4])
        }
      end

      # The vertices the test solid has once it is sliced for a bend: its
      # corners and where the slicing planes cut its long edges. In instance
      # coordinates.
      #
      # @param [Integer] axis
      # @param [Integer] subdivisions
      # @param [Boolean] tapered
      # @return [Array<Geom::Point3d>]
      def sliced_solid_points(axis, subdivisions = SUBDIVISIONS, tapered: true)
        (0..subdivisions).flat_map { |step|
          solid_section(axis, step.to_f / subdivisions, tapered: tapered)
        }
      end

      # @param [Integer] axis The axis the solid is long in.
      # @param [Geom::Transformation] transformation
      # @param [Boolean] tapered
      # @param [Sketchup::Entities] entities Where to add the group. The model
      #   by default.
      # @return [Sketchup::Group]
      def create_solid(axis, transformation = IDENTITY, tapered: true, entities: nil)
        entities ||= Sketchup.active_model.entities
        corners = solid_corners(axis, tapered: tapered)
        faces = [
          [0, 1, 2, 3], [4, 5, 6, 7],
          [0, 1, 5, 4], [1, 2, 6, 5], [2, 3, 7, 6], [3, 0, 4, 7],
        ]
        group = entities.add_group
        faces.each { |indices|
          group.entities.add_face(indices.map { |index| corners[index] })
        }
        group.transformation = transformation
        group
      end

      # Adds a loop of edges around the test solid, giving it vertices that the
      # slicing planes of a bend don't pass through.
      #
      # @param [Sketchup::Group] group
      # @param [Integer] axis
      # @param [Float] ratio
      # @param [Boolean] tapered
      def add_edge_loop(group, axis, ratio, tapered: true)
        points = solid_section(axis, ratio, tapered: tapered)
        points.each_with_index { |point, index|
          group.entities.add_line(point, points[(index + 1) % 4])
        }
      end

      # A group with only a rectangular face in it, which has no extent along
      # the given axis.
      #
      # @param [Integer] axis The axis the face is perpendicular to.
      # @return [Sketchup::Group]
      def create_flat_instance(axis)
        points = [
          point_along(axis, 0.0, 10.0, 5.0),
          point_along(axis, 0.0, 60.0, 5.0),
          point_along(axis, 0.0, 60.0, 25.0),
          point_along(axis, 0.0, 10.0, 25.0),
        ]
        group = Sketchup.active_model.entities.add_group
        group.entities.add_face(points)
        group
      end

      # The way the tool sets up the bend of an instance: along its red axis,
      # through its origin, towards the front of its bounding box.
      #
      # @param [Sketchup::Group, Sketchup::ComponentInstance] instance
      # @return [BendSetup]
      def bend_setup(instance)
        bender = TrueBendTool.new(instance).instance_variable_get(:@bender)
        BendSetup.new(bender.segment, bender.instance_variable_get(:@normal))
      end

      # The drag of the bend handle the tests bend with.
      #
      # @param [BendSetup] setup
      # @param [Boolean] towards Whether to bend towards the front of the
      #   instance, or away from it.
      # @return [Geom::Vector3d]
      def drag_vector(setup, towards)
        segment = setup.segment
        drag = towards ? setup.normal : setup.normal.reverse
        drag.length = segment.start.distance(segment.end).to_f * DRAG_RATIO
        drag
      end

      # @param [Sketchup::Group, Sketchup::ComponentInstance] instance
      # @param [BendSetup] setup
      # @param [Geom::Vector3d] drag
      # @param [Integer] subdivisions
      # @yieldparam [Bender] bender Yielded before the bend is committed, for
      #   setting it up further.
      # @return [Sketchup::Group, Sketchup::ComponentInstance]
      def commit_bend(instance, setup, drag, subdivisions: SUBDIVISIONS)
        bender = Bender.new(instance, setup.segment, setup.normal)
        bender.subdivisions = subdivisions
        bender.bend(drag)
        yield bender if block_given?
        model = Sketchup.active_model
        model.start_operation('Bend', true)
        bent = bender.commit
        model.commit_operation
        bent
      end

      # @param [Sketchup::Group, Sketchup::ComponentInstance] instance
      # @return [Array<Sketchup::Vertex>]
      def vertices_of(instance)
        edges = instance.definition.entities.grep(Sketchup::Edge)
        edges.flat_map(&:vertices).uniq
      end

      # @param [Sketchup::Group, Sketchup::ComponentInstance] instance
      # @return [Array<Geom::Point3d>] In instance coordinates.
      def local_positions(instance)
        vertices_of(instance).map(&:position)
      end

      # @param [Sketchup::Group, Sketchup::ComponentInstance] instance
      # @return [Array<Geom::Point3d>] In world coordinates.
      def world_positions(instance)
        local_positions(instance).map { |point|
          point.transform(instance.transformation)
        }
      end

      # The angle of a bend, in radians, from how far its handle is dragged.
      #
      # The reference segment keeps its length when bent, so bending it full
      # circle gives a circle with the segment's length as its circumference.
      # Dragging the handle by the diameter of that circle bends that far, and
      # shorter drags bend in proportion.
      #
      # @param [Array(Geom::Point3d, Geom::Point3d)] segment_points
      # @param [Geom::Vector3d] drag
      # @return [Float]
      def bend_angle(segment_points, drag)
        length = segment_points[0].distance(segment_points[1]).to_f
        full_circle_diameter = length / Math::PI
        2.0 * Math::PI * (drag.length.to_f / full_circle_diameter)
      end

      # Where a true circular bend moves the given points to.
      #
      # The reference segment is bent into an arc of the same length. Its mid
      # point stays in place, and the centre of the arc is straight off the mid
      # point, the way the handle is dragged.
      #
      # For every other point, three measures relative to the mid point decide
      # where it ends up:
      # * How far along the segment it is. It ends up that far along the arc.
      # * How far towards the centre it is. It ends up that much closer to the
      #   centre than the arc is.
      # * How far along the axis of the bend it is. This doesn't change.
      #
      # @param [Array<Geom::Point3d>] points In world coordinates.
      # @param [Array(Geom::Point3d, Geom::Point3d)] segment_points The ends of
      #   the reference segment, in world coordinates.
      # @param [Geom::Vector3d] drag The direction of the centre of the bend.
      # @param [Float] angle The angle of the bend, in radians.
      # @return [Array<Geom::Point3d>]
      def true_bend(points, segment_points, drag, angle = bend_angle(segment_points, drag))
        start, finish = segment_points
        along_axis = start.vector_to(finish).normalize
        inward_axis = drag.normalize
        bend_axis = along_axis * inward_axis
        mid_point = Geom.linear_combination(0.5, start, 0.5, finish)
        radius = start.distance(finish).to_f / angle
        centre = mid_point.offset(inward_axis, radius).to_a
        points.map { |point|
          offset = mid_point.vector_to(point)
          arc_angle = (offset % along_axis) / radius
          distance_from_centre = radius - (offset % inward_axis)
          along_bend_axis = offset % bend_axis
          coordinates = Array.new(3) { |i|
            outward = (Math.sin(arc_angle) * along_axis[i]) - (Math.cos(arc_angle) * inward_axis[i])
            centre[i] + (distance_from_centre * outward) + (along_bend_axis * bend_axis[i])
          }
          Geom::Point3d.new(coordinates)
        }
      end

      # Asserts that the two sets of points are the same, in any order.
      #
      # @param [Array<Geom::Point3d>] expected
      # @param [Array<Geom::Point3d>] actual
      # @param [String] message
      def assert_same_points(expected, actual, message = nil)
        unmatched = actual.dup
        missing = []
        expected.each { |point|
          index = unmatched.index { |candidate| candidate.distance(point).to_f < TOLERANCE }
          index ? unmatched.delete_at(index) : missing << point
        }
        return pass if missing.empty? && unmatched.empty?

        details = []
        unless missing.empty?
          nearest = actual.map { |point| point.distance(missing.first).to_f }.min
          details << "#{missing.size} of #{expected.size} expected points were not found, " \
                     "such as #{missing.first.to_a.inspect}, which the nearest point is " \
                     "#{nearest.inspect} away from"
        end
        unless unmatched.empty?
          details << "#{unmatched.size} of #{actual.size} points were not expected, " \
                     "such as #{unmatched.first.to_a.inspect}"
        end
        flunk([message, *details].compact.join("\n"))
      end

      # @param [Geom::Point3d] expected
      # @param [Geom::Point3d] actual
      # @param [String] message
      def assert_point(expected, actual, message = nil)
        distance = expected.distance(actual).to_f
        description = "Expected #{actual.to_a.inspect} to be at #{expected.to_a.inspect}"
        assert_operator(distance, :<, TOLERANCE, [message, description].compact.join("\n"))
      end

      # Asserts that the vectors have the same direction and length.
      #
      # @param [Geom::Vector3d] expected
      # @param [Geom::Vector3d] actual
      # @param [String] message
      def assert_vector(expected, actual, message = nil)
        difference = (expected - actual).length.to_f
        description = "Expected #{actual.to_a.inspect} to be #{expected.to_a.inspect}"
        assert_operator(difference, :<, TOLERANCE, [message, description].compact.join("\n"))
      end

    end # module
  end # module
end # module
