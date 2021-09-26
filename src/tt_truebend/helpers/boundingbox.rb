require 'tt_truebend/constants/boundingbox'
require 'tt_truebend/geom/segment'
require 'tt_truebend/geom/polygon'

module TT::Plugins::TrueBend
  module BoundingBoxHelper

    include BoundingBoxConstants

    # @return [Array<Geom::Point3d>]
    def points
      Array.new(8) { |i| corner(i) }
    end

    # @return [Array<Geom::Point3d>]
    def segment_points
      [
        corner(BB_LEFT_FRONT_BOTTOM),
        corner(BB_RIGHT_FRONT_BOTTOM),

        corner(BB_RIGHT_FRONT_BOTTOM),
        corner(BB_RIGHT_FRONT_TOP),

        corner(BB_RIGHT_FRONT_TOP),
        corner(BB_LEFT_FRONT_TOP),

        corner(BB_LEFT_FRONT_TOP),
        corner(BB_LEFT_FRONT_BOTTOM),

        corner(BB_LEFT_BACK_BOTTOM),
        corner(BB_RIGHT_BACK_BOTTOM),

        corner(BB_RIGHT_BACK_BOTTOM),
        corner(BB_RIGHT_BACK_TOP),

        corner(BB_RIGHT_BACK_TOP),
        corner(BB_LEFT_BACK_TOP),

        corner(BB_LEFT_BACK_TOP),
        corner(BB_LEFT_BACK_BOTTOM),

        corner(BB_LEFT_FRONT_BOTTOM),
        corner(BB_LEFT_BACK_BOTTOM),

        corner(BB_RIGHT_FRONT_BOTTOM),
        corner(BB_RIGHT_BACK_BOTTOM),

        corner(BB_RIGHT_FRONT_TOP),
        corner(BB_RIGHT_BACK_TOP),

        corner(BB_LEFT_FRONT_TOP),
        corner(BB_LEFT_BACK_TOP),
      ]
    end

    # @return [Array<Segment>]
    def segments
      segment_points.each_slice(2).map { |segment| Segment.new(*segment) }
    end

    # @param [Integer] index
    # @return [Polygon]
    def polygon(index)
      polygons[index]
    end

    # @return [Array<Polygon>]
    def polygons # rubocop:disable Metrics/MethodLength
      [
        Polygon.new(
            corner(BB_LEFT_FRONT_BOTTOM),
            corner(BB_RIGHT_FRONT_BOTTOM),
            corner(BB_RIGHT_FRONT_TOP),
            corner(BB_LEFT_FRONT_TOP)
        ),
        Polygon.new(
            corner(BB_RIGHT_FRONT_BOTTOM),
            corner(BB_RIGHT_BACK_BOTTOM),
            corner(BB_RIGHT_BACK_TOP),
            corner(BB_RIGHT_FRONT_TOP)
        ),
        Polygon.new(
            corner(BB_RIGHT_BACK_BOTTOM),
            corner(BB_LEFT_BACK_BOTTOM),
            corner(BB_LEFT_BACK_TOP),
            corner(BB_RIGHT_BACK_TOP)
        ),
        Polygon.new(
            corner(BB_LEFT_BACK_BOTTOM),
            corner(BB_LEFT_FRONT_BOTTOM),
            corner(BB_LEFT_FRONT_TOP),
            corner(BB_LEFT_BACK_TOP)
        ),
        Polygon.new(
            corner(BB_LEFT_FRONT_TOP),
            corner(BB_RIGHT_FRONT_TOP),
            corner(BB_RIGHT_BACK_TOP),
            corner(BB_LEFT_BACK_TOP)
        ),
        Polygon.new(
            corner(BB_RIGHT_BACK_BOTTOM),
            corner(BB_LEFT_BACK_BOTTOM),
            corner(BB_LEFT_FRONT_BOTTOM),
            corner(BB_RIGHT_FRONT_BOTTOM)
        ),
      ]
    end

  end
end # module
