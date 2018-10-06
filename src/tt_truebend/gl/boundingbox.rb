require 'tt_truebend/constants/boundingbox'
require 'tt_truebend/constants/view'
require 'tt_truebend/helpers/boundingbox'
require 'tt_truebend/helpers/instance'
require 'tt_truebend/gl/drawing_helper'

module TT::Plugins::TrueBend
  class BoundingBoxWidget

    include BoundingBoxConstants
    include DrawingHelper
    include InstanceHelper
    include ViewConstants

    def initialize(instance, color: [255, 128, 0], line_width: 2)
      @instance = instance
      @color = Sketchup::Color.new(*color)
      @line_width = line_width
    end

    def bounds
      @instance.bounds
    end

    def width
      (local_bounds.width * scale_x).to_l
    end

    def height
      (local_bounds.height * scale_y).to_l
    end

    def depth
      (local_bounds.depth * scale_z).to_l
    end

    def diagonal
      pts = points
      pts[BB_LEFT_FRONT_BOTTOM].distance(pts[BB_RIGHT_BACK_TOP])
    end

    def points
      local_bounds.points.map { |point|
        point.transform(@instance.transformation)
      }
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

    def scaling_transformation
      Geom::Transformation.scaling(scale_x, scale_y, scale_z)
    end

    def scale_x
      X_AXIS.transform(@instance.transformation).length.to_f
    end

    def scale_y
      Y_AXIS.transform(@instance.transformation).length.to_f
    end

    def scale_z
      Z_AXIS.transform(@instance.transformation).length.to_f
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
      extended_bounds = definition(@instance).bounds
      extended_bounds.extend(BoundingBoxHelper)
      extended_bounds
    end

    def segment_points
      points = local_bounds.segment_points
      points.each { |point| point.transform!(@instance.transformation) }
    end

  end # class
end # module
