require 'tt_truebend/constants/view'
require 'tt_truebend/helpers/boundingbox'
require 'tt_truebend/gl/drawing_helper'

module TT::Plugins::TrueBend
  class BoundingBoxWidget

    include DrawingHelper
    include ViewConstants

    def initialize(instance, color: [255, 128, 0], line_width: 2)
      @instance = instance
      @color = Sketchup::Color.new(*color)
      @line_width = line_width
    end

    def bounds
      @instance.bounds
    end

    def polygon(index)
      polygon = local_bounds.polygon(index)
      polygon.transform!(@instance.transformation)
      polygon
    end

    def polygons
      local_bounds.polygons.map { |polygon|
        polygon.transform!(@instance.transformation)
      }
    end

    def segments
      local_bounds.segments.map { |polygon|
        polygon.transform!(@instance.transformation)
      }
    end

    def draw(view)
      points = lift!(view, segment_points, pixels: 0.2)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = @line_width
      view.drawing_color = @color
      view.draw(GL_LINES, points)
    end

    private

    def local_bounds
      @instance.definition.bounds.extend(BoundingBoxHelper)
    end

    def segment_points
      points = local_bounds.segment_points
      points.each { |point| point.transform!(@instance.transformation) }
    end

  end # class
end # module
