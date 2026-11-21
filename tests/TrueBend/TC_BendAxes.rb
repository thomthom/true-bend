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
    class TC_BendAxes < TestUp::TestCase

      include TrueBendTestUtilities

      X = BendAxes::X
      Y = BendAxes::Y
      Z = BendAxes::Z

      # The bounds of the test instance, in its own coordinates.
      BOUNDS_MIN = Geom::Point3d.new(10, 20, 30)
      BOUNDS_MAX = Geom::Point3d.new(110, 60, 50)

      ROTATION = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 2, 3), 37.degrees)
      TRANSLATION = Geom::Transformation.translation(Geom::Vector3d.new(30, -40, 50))

      PLACEMENTS = {
        'unrotated'            => IDENTITY,
        'tilted about red'     => Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees),
        'rotated and moved'    => TRANSLATION * ROTATION,
        'scaled non-uniformly' => ROTATION * Geom::Transformation.scaling(2, 0.5, 1.5),
        'mirrored along red'   => ROTATION * Geom::Transformation.scaling(-1, 1, 1),
        'mirrored along green' => ROTATION * Geom::Transformation.scaling(1, -1, 1),
        'mirrored along blue'  => ROTATION * Geom::Transformation.scaling(1, 1, -1),
      }.freeze

      def setup
        start_with_empty_model
      end

      def teardown
        # ...
      end


      # @param [Geom::Transformation] transformation
      # @return [Sketchup::Group] A box that doesn't start at the group origin.
      def create_box(transformation = IDENTITY)
        group = Sketchup.active_model.entities.add_group
        x1, y1, z1 = BOUNDS_MIN.to_a
        x2, y2, = BOUNDS_MAX.to_a
        face = group.entities.add_face([x1, y1, z1], [x2, y1, z1], [x2, y2, z1], [x1, y2, z1])
        face.reverse! if face.normal.z < 0
        face.pushpull(BOUNDS_MAX.z - BOUNDS_MIN.z)
        group.transformation = transformation
        group
      end

      # Yields every way of bending a box, for each of the test placements.
      #
      # @yieldparam [BendAxes] axes
      # @yieldparam [Geom::Transformation] transformation
      # @yieldparam [String] description
      def each_bend
        PLACEMENTS.each { |placement, transformation|
          instance = create_box(transformation)
          [X, Y, Z].each { |axis|
            BendAxes.along(instance, axis).each_with_index { |axes, index|
              yield axes, transformation, "#{placement}, along #{AXIS_NAMES[axis]}, face #{index}"
            }
          }
        }
      end

      # @param [BendAxes] axes
      # @return [Geom::Vector3d]
      def segment_direction(axes)
        segment = axes.segment
        segment.start.vector_to(segment.end)
      end


      def test_along_offers_two_faces_for_each_axis
        instance = create_box
        [X, Y, Z].each { |axis|
          options = BendAxes.along(instance, axis)
          assert_equal(2, options.size, AXIS_NAMES[axis])
          assert_equal([axis, axis], options.map(&:axis), AXIS_NAMES[axis])
        }
      end

      def test_segment_runs_along_the_axis_through_the_origin
        instance = create_box
        expected = [
          [Geom::Point3d.new(10, 0, 0), Geom::Point3d.new(110, 0, 0)],
          [Geom::Point3d.new(0, 20, 0), Geom::Point3d.new(0, 60, 0)],
          [Geom::Point3d.new(0, 0, 30), Geom::Point3d.new(0, 0, 50)],
        ]
        [X, Y, Z].each { |axis|
          BendAxes.along(instance, axis).each { |axes|
            segment = axes.segment
            assert_kind_of(Segment, segment)
            assert_point(expected[axis][0], segment.start, "Start along #{AXIS_NAMES[axis]}")
            assert_point(expected[axis][1], segment.end, "End along #{AXIS_NAMES[axis]}")
          }
        }
      end

      def test_segment_follows_the_instance
        each_bend { |axes, transformation, description|
          start = [0, 0, 0]
          start[axes.axis] = BOUNDS_MIN[axes.axis]
          finish = [0, 0, 0]
          finish[axes.axis] = BOUNDS_MAX[axes.axis]
          segment = axes.segment
          assert_point(Geom::Point3d.new(start).transform(transformation), segment.start,
                       "Start, #{description}")
          assert_point(Geom::Point3d.new(finish).transform(transformation), segment.end,
                       "End, #{description}")
        }
      end

      def test_normal_is_the_outward_direction_of_the_face
        instance = create_box
        front = Y_AXIS.reverse
        expected = [[front, Z_AXIS], [X_AXIS, Z_AXIS], [front, X_AXIS]]
        [X, Y, Z].each { |axis|
          normals = BendAxes.along(instance, axis).map(&:normal)
          assert_vector(expected[axis][0], normals[0], "Default along #{AXIS_NAMES[axis]}")
          assert_vector(expected[axis][1], normals[1], "Alternative along #{AXIS_NAMES[axis]}")
        }
      end

      def test_normal_is_unit_length
        each_bend { |axes, _transformation, description|
          assert_in_delta(1.0, axes.normal.length.to_f, 1.0e-9, description)
        }
      end

      def test_normal_is_perpendicular_to_the_segment
        each_bend { |axes, _transformation, description|
          direction = segment_direction(axes).normalize
          assert_in_delta(0.0, axes.normal % direction, 1.0e-9, description)
        }
      end

      def test_normal_points_out_of_the_bounds
        each_bend { |axes, transformation, description|
          centre = Geom.linear_combination(0.5, BOUNDS_MIN, 0.5, BOUNDS_MAX)
          outwards = centre.transform(transformation).vector_to(axes.face_center)
          assert_in_delta(1.0, axes.normal % outwards.normalize, 1.0e-9, description)
        }
      end

      def test_face_center
        instance = create_box
        front = Geom::Point3d.new(60, 20, 40)
        right = Geom::Point3d.new(110, 40, 40)
        top = Geom::Point3d.new(60, 40, 50)
        expected = [[front, top], [right, top], [front, right]]
        [X, Y, Z].each { |axis|
          centers = BendAxes.along(instance, axis).map(&:face_center)
          assert_point(expected[axis][0], centers[0], "Default along #{AXIS_NAMES[axis]}")
          assert_point(expected[axis][1], centers[1], "Alternative along #{AXIS_NAMES[axis]}")
        }
      end

      def test_face_center_follows_the_instance
        local = {
          BendAxes::FRONT => Geom::Point3d.new(60, 20, 40),
          BendAxes::RIGHT => Geom::Point3d.new(110, 40, 40),
          BendAxes::TOP   => Geom::Point3d.new(60, 40, 50),
        }
        PLACEMENTS.each { |placement, transformation|
          instance = create_box(transformation)
          BendAxes::FACES.each_with_index { |faces, axis|
            faces.each { |face|
              axes = BendAxes.new(instance, axis, face)
              assert_point(local[face].transform(transformation), axes.face_center,
                           "#{placement}, along #{AXIS_NAMES[axis]}, #{FACE_NAMES[face]}")
            }
          }
        }
      end

      def test_can_bend_box
        instance = create_box
        [X, Y, Z].each { |axis|
          BendAxes.along(instance, axis).each { |axes|
            assert(axes.can_bend?, AXIS_NAMES[axis])
          }
        }
      end

      def test_can_bend_flat_instance
        [X, Y, Z].each { |flat_axis|
          instance = create_flat_instance(flat_axis)
          [X, Y, Z].each { |axis|
            BendAxes.along(instance, axis).each { |axes|
              message = "Along #{AXIS_NAMES[axis]}, with no extent along #{AXIS_NAMES[flat_axis]}"
              assert_equal(axis != flat_axis, axes.can_bend?, message)
            }
          }
        }
      end

      def test_can_bend_line_instance
        [X, Y, Z].each { |line_axis|
          instance = create_line_instance(line_axis)
          [X, Y, Z].each { |axis|
            BendAxes.along(instance, axis).each { |axes|
              message = "Along #{AXIS_NAMES[axis]}, with only a line along #{AXIS_NAMES[line_axis]}"
              assert_equal(axis == line_axis, axes.can_bend?, message)
            }
          }
        }
      end

    end # class
  end # module
end # module
