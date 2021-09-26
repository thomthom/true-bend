module TT::Plugins::TrueBend
  class PolarProjection

    PI2 = Math::PI * 2

    # The radius represents where the Cartesian X axis will be mapped to in the
    # polar coordinates.
    attr_accessor :radius

    # Transformation applied to the projected points.
    attr_accessor :transformation

    # @param [Float] radius
    def initialize(radius)
      @radius = radius
      @transformation = nil
    end

    # Sets the target transformation based on origin and x-axis.
    #
    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] x_axis
    def axes(origin, x_axis)
      y_axis = x_axis.axes.x
      z_axis = x_axis.axes.y
      @transformation = Geom::Transformation.axes(origin, x_axis, y_axis, z_axis)
      nil
    end

    # @param [Array<Geom::Point3d>] points
    # @param [Boolean] convex
    # @param [Float, nil] segment_angle
    # @return [Array<Geom::Point3d>]
    def project(points, convex, segment_angle = nil)
      tr = convex ? Geom::Transformation.scaling(1, -1, 1) :
                    Geom::Transformation.scaling(-1, 1, 1)
      offset_index = convex ? 1 : -1
      circumference = Math::PI * (radius * 2)
      projected = points.map { |local_point|
        # Map the X coordinate to an angular value in the Polar coordinate
        # system. The circumference at `radius` (Y=0) is considered the target
        # range for the X coordinate.
        point = local_point.transform(tr)
        angle = PI2 * (point.x / circumference)
        polar_point = project_point(point, angle)
        if segment_angle
          segment = (angle / segment_angle).to_i
          a1 = segment_angle * segment
          a2 = segment_angle * (segment + offset_index)
          pt1 = project_point(point, a1)
          pt2 = project_point(point, a2)
          chord = [pt1, pt2]
          polar_origin = Geom::Point3d.new(0, 0, local_point.z)
          projection = [polar_origin, polar_point]
          polar_point = Geom.intersect_line_line(projection, chord)
        end
        polar_point
      }
      projected.each { |pt| pt.transform!(@transformation) } if @transformation
      projected
    end

    private

    # @param [Geom::Point3d] point
    # @param [Float] angle
    # @return [Geom::Point3d]
    def project_point(point, angle)
      x = (radius + point.y) * Math.cos(angle)
      y = (radius + point.y) * Math.sin(angle)
      Geom::Point3d.new(x, y, point.z)
    end

  end
end # module
