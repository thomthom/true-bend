#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

require 'testup/testcase'
require_relative '../lib/test_utilities'

require 'tt_truebend/geom/segment'

module TT::Plugins::TrueBend
  module Tests
    class TC_Segment < TestUp::TestCase

      include TrueBendTestUtilities

      def setup
        # ...
      end

      def teardown
        # ...
      end


      # @return [Segment] From (10, 20, 30) to (40, 60, 30); 50" long.
      def create_segment
        Segment.new(Geom::Point3d.new(10, 20, 30), Geom::Point3d.new(40, 60, 30))
      end

      # @param [Float] x
      # @return [Array(Geom::Point3d, Geom::Vector3d)] A plane across the red
      #   axis.
      def plane_at(x)
        [Geom::Point3d.new(x, 0, 0), X_AXIS]
      end


      def test_initialize_copies_the_points
        point1 = Geom::Point3d.new(1, 2, 3)
        point2 = Geom::Point3d.new(4, 5, 6)
        segment = Segment.new(point1, point2)

        point1.x = 100
        point2.x = 100

        assert_point(Geom::Point3d.new(1, 2, 3), segment.start)
        assert_point(Geom::Point3d.new(4, 5, 6), segment.end)
      end

      def test_points
        segment = create_segment

        assert_equal(2, segment.points.size)
        assert_point(Geom::Point3d.new(10, 20, 30), segment.points[0])
        assert_point(Geom::Point3d.new(40, 60, 30), segment.points[1])
        assert_point(segment.points[0], segment.start)
        assert_point(segment.points[1], segment.end)
      end

      def test_length
        assert_in_delta(50.0, create_segment.length.to_f, TOLERANCE)
      end

      def test_direction
        assert_vector(Geom::Vector3d.new(30, 40, 0), create_segment.direction)
      end

      def test_line
        point, vector = create_segment.line

        assert_point(Geom::Point3d.new(10, 20, 30), point)
        assert_vector(Geom::Vector3d.new(30, 40, 0), vector)
      end

      def test_mid_point
        assert_point(Geom::Point3d.new(25, 40, 30), create_segment.mid_point)
      end

      def test_intersect_plane
        point = create_segment.intersect_plane(plane_at(16))

        assert_point(Geom::Point3d.new(16, 28, 30), point)
      end

      def test_intersect_plane_beyond_the_ends
        segment = create_segment

        assert_nil(segment.intersect_plane(plane_at(5)), 'Before the start')
        assert_nil(segment.intersect_plane(plane_at(45)), 'After the end')
      end

      def test_intersect_plane_at_the_ends
        segment = create_segment

        assert_nil(segment.intersect_plane(plane_at(10)), 'At the start')
        assert_nil(segment.intersect_plane(plane_at(40)), 'At the end')
      end

      def test_intersect_plane_parallel
        plane = [Geom::Point3d.new(0, 0, 10), Z_AXIS]

        assert_nil(create_segment.intersect_plane(plane))
      end

      def test_intersect_plane_segment_without_length
        point = Geom::Point3d.new(10, 20, 30)
        segment = Segment.new(point, point)

        assert_nil(segment.intersect_plane(plane_at(10)))
      end

      def test_split
        segment = create_segment

        result = segment.split(plane_at(16))

        assert_equal(2, result.size)
        assert_kind_of(Segment, result[0])
        assert_kind_of(Segment, result[1])
        assert_point(Geom::Point3d.new(10, 20, 30), result[0].start)
        assert_point(Geom::Point3d.new(16, 28, 30), result[0].end)
        assert_point(Geom::Point3d.new(16, 28, 30), result[1].start)
        assert_point(Geom::Point3d.new(40, 60, 30), result[1].end)
      end

      def test_split_not_crossing_the_plane
        segment = create_segment

        result = segment.split(plane_at(45))

        assert_equal([segment], result)
      end

      def test_transform
        segment = create_segment
        transformation = Geom::Transformation.translation(Geom::Vector3d.new(1, 2, 3))

        result = segment.transform(transformation)

        refute_same(segment, result)
        assert_point(Geom::Point3d.new(11, 22, 33), result.start)
        assert_point(Geom::Point3d.new(41, 62, 33), result.end)
        assert_point(Geom::Point3d.new(10, 20, 30), segment.start, 'Original')
        assert_point(Geom::Point3d.new(40, 60, 30), segment.end, 'Original')
      end

      def test_transform_in_place
        segment = create_segment
        transformation = Geom::Transformation.translation(Geom::Vector3d.new(1, 2, 3))

        result = segment.transform!(transformation)

        assert_same(segment, result)
        assert_point(Geom::Point3d.new(11, 22, 33), segment.start)
        assert_point(Geom::Point3d.new(41, 62, 33), segment.end)
      end

    end # class
  end # module
end # module
