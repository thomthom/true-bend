#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

module TT::Plugins::TrueBend

  module ViewConstants

    # Constants for Sketchup::View.draw_points

    DRAW_OPEN_SQUARE     = 1
    DRAW_FILLED_SQUARE   = 2
    DRAW_PLUS            = 3
    DRAW_CROSS           = 4
    DRAW_STAR            = 5
    DRAW_OPEN_TRIANGLE   = 6
    DRAW_FILLED_TRIANGLE = 7


    # Constants for Sketchup::View.line_stipple

    STIPPLE_SOLID = ''.freeze
    STIPPLE_DOTTED = '.'.freeze
    STIPPLE_SHORT_DASH = '-'.freeze
    STIPPLE_LONG_DASH = '_'.freeze
    STIPPLE_DASH_DOT_DASH = '-.-'.freeze

  end

end # module
