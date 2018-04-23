module TT::Plugins::TrueBend
  module DrawingHelper

    # @param [Sketchup::View] view
    # @param [Array(Geom::Point3d, Geom::Vector3d)] plane
    # @param [Numeric] size
    # @param [Sketchup::Color] color
    # @return [nil]
    def draw_plane(view, plane, size, color)
      color = Sketchup::Color.new(color)
      points = [
        Geom::Point3d.new(-0.5, -0.5, 0),
        Geom::Point3d.new( 0.5, -0.5, 0),
        Geom::Point3d.new( 0.5,  0.5, 0),
        Geom::Point3d.new(-0.5,  0.5, 0),
      ]
      # Scale and orient.
      tr_scale = Geom::Transformation.scaling(size)
      origin, z_axis = plane
      tr_axes = Geom::Transformation.new(origin, z_axis)
      tr = tr_axes * tr_scale
      points.each { |pt| pt.transform!(tr) }
      # Draw transparent fill and solid outline.
      view.drawing_color = color
      view.line_stipple = STIPPLE_LONG_DASH
      view.line_width = 2
      view.draw(GL_LINE_LOOP, points)
      color.alpha = 0.1
      view.drawing_color = color
      view.draw(GL_QUADS, points)
      nil
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] points
    # @param [Integer] pixels
    # @return [Array<Geom::Point3d>]
    def lift(view, points, pixels: 1)
      lift!(view, points.map(&:clone), pixels: pixels)
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] points
    # @param [Integer] pixels
    # @return [Array<Geom::Point3d>]
    def lift!(view, points, pixels: 1)
      direction = view.camera.direction.reverse
      points.each { |point|
        # Take one pixel and multiply with the pixel value to allow for
        # fractional offset.
        distance = view.pixels_to_model(1, point) * pixels
        point.offset!(direction, distance)
      }
    end

  end
end # module
