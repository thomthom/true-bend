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
    # The grid the `Bender` draws over the instance, to preview how the bend
    # maps it.
    class TC_Bender_Grid < TestUp::TestCase

      include TrueBendTestUtilities

      ROTATION = Geom::Transformation.rotation(ORIGIN, Geom::Vector3d.new(1, 2, 3), 37.degrees)
      TRANSLATION = Geom::Transformation.translation(Geom::Vector3d.new(30, -40, 50))

      PLACEMENTS = {
        'unrotated'           => IDENTITY,
        'tilted about red'    => Geom::Transformation.rotation(ORIGIN, X_AXIS, 90.degrees),
        'rotated and moved'   => TRANSLATION * ROTATION,
        'scaled and mirrored' => ROTATION * Geom::Transformation.scaling(-2, 0.5, 1.5),
      }.freeze

      def setup
        start_with_empty_model
      end

      def teardown
        # ...
      end


      # @param [Bender] bender
      # @return [Grid]
      def grid_of(bender)
        bender.instance_variable_get(:@grid)
      end

      # Yields a `Bender` for every way of bending the test solid, for each of
      # the test placements.
      #
      # @yieldparam [Bender] bender
      # @yieldparam [BendAxes] axes
      # @yieldparam [Array<Geom::Point3d>] corners The corners of the solid, in
      #   world coordinates.
      # @yieldparam [String] description
      def each_bender
        PLACEMENTS.each { |placement, transformation|
          BendAxes::FACES.each_index { |axis|
            instance = create_solid(axis, transformation)
            corners = solid_corners(axis).map { |point| point.transform(transformation) }
            BendAxes.along(instance, axis).each_with_index { |axes, index|
              bender = Bender.new(instance, axes.segment, axes.normal)
              yield bender, axes, corners, "#{placement}, along #{AXIS_NAMES[axis]}, face #{index}"
            }
          }
        }
      end

      # The extents of the points in the given direction, measured from the
      # start of the reference segment.
      #
      # @param [Array<Geom::Point3d>] points
      # @param [BendAxes] axes
      # @param [Geom::Vector3d] direction Unit vector.
      # @return [Array(Float, Float)]
      def extents(points, axes, direction)
        start = axes.segment.start
        points.map { |point| start.vector_to(point) % direction }.minmax
      end

      # @param [Array(Float, Float)] expected
      # @param [Array(Float, Float)] actual
      # @param [String] message
      def assert_extents(expected, actual, message)
        assert_in_delta(expected[0], actual[0], TOLERANCE, "Lower extent, #{message}")
        assert_in_delta(expected[1], actual[1], TOLERANCE, "Upper extent, #{message}")
      end


      def test_grid_spans_the_reference_segment
        each_bender { |bender, axes, _corners, description|
          segment = axes.segment
          length = segment.start.distance(segment.end).to_f
          along = segment.start.vector_to(segment.end).normalize
          points = grid_of(bender).segment_points
          assert_extents([0.0, length], extents(points, axes, along), description)
        }
      end

      def test_grid_spans_the_instance_in_the_direction_of_the_bend
        each_bender { |bender, axes, corners, description|
          points = grid_of(bender).segment_points
          assert_extents(extents(corners, axes, axes.normal),
                         extents(points, axes, axes.normal), description)
        }
      end

      def test_grid_lies_flat_on_a_side_of_the_instance
        each_bender { |bender, axes, corners, description|
          segment = axes.segment
          bend_axis = (segment.start.vector_to(segment.end) * axes.normal).normalize
          lower, upper = extents(grid_of(bender).segment_points, axes, bend_axis)
          assert_in_delta(lower, upper, TOLERANCE, "Flat, #{description}")
          sides = extents(corners, axes, bend_axis)
          on_a_side = sides.any? { |side| (side - lower).abs < TOLERANCE }
          assert(on_a_side, "Expected the grid at #{lower} to be on a side of the instance, " \
                            "which are at #{sides.inspect}. #{description}")
        }
      end

      def test_grid_is_divided_like_the_reference_segment
        each_bender { |bender, axes, _corners, description|
          bender.subdivisions = 5
          segment = axes.segment
          length = segment.start.distance(segment.end).to_f
          along = segment.start.vector_to(segment.end).normalize
          points = grid_of(bender).segment_points
          positions = points.map { |point| (segment.start.vector_to(point) % along).round(6) }
          expected = Array.new(6) { |i| (length * i / 5.0).round(6) }
          assert_equal(expected, positions.uniq.sort, description)
        }
      end

      def test_grid_has_the_default_number_of_subdivisions
        instance = create_solid(BendAxes::X)
        axes = BendAxes.along(instance, BendAxes::X).first

        bender = Bender.new(instance, axes.segment, axes.normal)

        assert_equal(24, bender.subdivisions)
        assert_equal(24, grid_of(bender).x_subdivs)
        # The grid is made of segments between each of its lines: 24 along by
        # the 4 lines across, and 3 across by the 25 lines along.
        assert_equal((24 * 4) + (3 * 25), grid_of(bender).segments.size)
      end

      def test_set_subdivisions_keeps_the_grid_in_sync
        instance = create_solid(BendAxes::X)
        axes = BendAxes.along(instance, BendAxes::X).first
        bender = Bender.new(instance, axes.segment, axes.normal)
        grid = grid_of(bender)

        bender.subdivisions = 8

        assert_equal(8, bender.subdivisions)
        assert_same(grid, grid_of(bender))
        assert_equal(8, grid.x_subdivs)
        # The grid is made of segments between each of its lines: 8 along by
        # the 4 lines across, and 3 across by the 9 lines along.
        assert_equal((8 * 4) + (3 * 9), grid.segments.size)
      end

    end # class
  end # module
end # module
