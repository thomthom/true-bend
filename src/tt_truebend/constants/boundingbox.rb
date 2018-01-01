#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

module TT::Plugins::TrueBend

  module BoundingBoxConstants

    # Constants for Geom::BoundingBox.corner

    BB_LEFT_FRONT_BOTTOM  = 0
    BB_RIGHT_FRONT_BOTTOM = 1
    BB_LEFT_BACK_BOTTOM   = 2
    BB_RIGHT_BACK_BOTTOM  = 3
    BB_LEFT_FRONT_TOP     = 4
    BB_RIGHT_FRONT_TOP    = 5
    BB_LEFT_BACK_TOP      = 6
    BB_RIGHT_BACK_TOP     = 7


    # Constants for BoundingBoxHelper.polygons

    BB_POLYGON_FRONT  = 0
    BB_POLYGON_RIGHT  = 1
    BB_POLYGON_BACK   = 2
    BB_POLYGON_LEFT   = 3
    BB_POLYGON_TOP    = 4
    BB_POLYGON_BOTTOM = 5

  end

end # module
