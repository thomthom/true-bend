require 'tt_truebend/constants/view'
require 'tt_truebend/gl/drawing_helper'

module TT::Plugins::TrueBend
  class SubdividedSegmentWidget

    include DrawingHelper
    include ViewConstants

    attr_accessor :segment
    attr_accessor :subdivisions, :color, :line_width

    def initialize(segment, subdivisions: 12, color: [255, 128, 0], line_width: 2)
      @segment = segment
      @subdivisions = subdivisions
      @color = Sketchup::Color.new(*color)
      @line_width = line_width
    end

    def bounds
      bounds = Geom::BoundingBox.new
      bounds.add(segment.points)
      bounds
    end

    def points
      point1, point2 = @segment.points
      num_points = subdivisions.to_f
      (0..subdivisions).map { |i|
        w1 = i.to_f / num_points
        w2 = 1.0 - w1
        Geom.linear_combination(w1, point1, w2, point2)
      }
    end

    def draw(view)
      segment_points = lift(view, @segment.points, pixels: 0.4)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = @line_width
      view.drawing_color = @color
      view.draw(GL_LINES, segment_points)

      view.draw_points(points, 6, DRAW_FILLED_SQUARE, @color)
    end

  end # class
end # module
