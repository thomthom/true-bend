module TT::Plugins::TrueBend
  module DrawingHelper

    include ViewConstants

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
      tr_scale = Geom::Transformation.scaling(size, size, size)
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

    # Sets the drawing colour to the one SketchUp draws the given axis in. The
    # user can change these colours in the preferences.
    #
    # @param [Sketchup::View] view
    # @param [Integer] axis 0, 1 or 2 for the red, green or blue axis.
    # @return [nil]
    def set_axis_color(view, axis)
      # SketchUp picks the colour from how a line runs relative to the drawing
      # axes of the model, which the user can move.
      model = view.model
      axes = model.respond_to?(:axes) ? model.axes.axes : [X_AXIS, Y_AXIS, Z_AXIS]
      view.set_color_from_line(ORIGIN, ORIGIN.offset(axes[axis]))
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
