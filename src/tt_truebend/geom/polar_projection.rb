module TT::Plugins::TrueBend
  class PolarProjection

    PI2 = Math::PI * 2

    # The radius represents where the Cartesian X axis will be mapped to in the
    # polar coordinates.
    attr_accessor :radius

    # Transformation applied to the projected points.
    attr_accessor :transformation

    def initialize(radius)
      @radius = radius
      @transformation = nil
    end

    # Sets the target transformation based on orgin and x-axis.
    def axes(origin, x_axis)
      y_axis = x_axis.axes.x
      z_axis = x_axis.axes.y
      @transformation = Geom::Transformation.axes(origin, x_axis, y_axis, z_axis)
      nil
    end

    def project(points, convex)
      tr = convex ? Geom::Transformation.scaling(1, -1, 1) :
                    Geom::Transformation.scaling(-1, 1, 1)
      circumference = Math::PI * (radius * 2)
      projected = points.map { |point|
        # Map the X coordinate to an angular value in the Polar coordinate
        # system. The circumference at `radius` (Y=0) is considered the target
        # range for the X coordinate.
        point = point.transform(tr)
        angle = PI2 * (point.x / circumference)
        x = (radius + point.y) * Math.cos(angle)
        y = (radius + point.y) * Math.sin(angle)
        Geom::Point3d.new(x, y, point.z)
      }
      projected.each { |pt| pt.transform!(@transformation) } if @transformation
      projected
    end

  end
end # module
