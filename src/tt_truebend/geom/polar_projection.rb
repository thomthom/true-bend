module TT::Plugins::TrueBend
  class PolarProjection

    PI2 = Math::PI * 2

    # The radius represents where the Cartesian X axis will be mapped to in the
    # polar coordinates.
    attr_accessor :radius

    def initialize(radius)
      @radius = radius
    end

    def project(points)
      circumference = Math::PI * (radius * 2)
      points.map { |point|
        # Map the X coordinate to an angular value in the Polar coordinate
        # system. The circumference at `radius` (Y=0) is considered the target
        # range for the X coordinate.
        angle = PI2 * (point.x / circumference)
        x = (radius + point.y) * Math.cos(angle)
        y = (radius + point.y) * Math.sin(angle)
        Geom::Point3d.new(x, y, 0)
      }
    end

  end
end # module
