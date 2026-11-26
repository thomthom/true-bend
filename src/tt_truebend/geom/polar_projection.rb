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

    # Sets the target transformation based on the origin of the polar
    # coordinates, the direction of angle zero and the axis the angles revolve
    # around.
    #
    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] x_axis
    # @param [Geom::Vector3d] z_axis Must be perpendicular to `x_axis`.
    def axes(origin, x_axis, z_axis)
      y_axis = z_axis * x_axis
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

    # Projects triangles the way {#project} projects their points, and turns
    # the normals of their vertices to follow the projection.
    #
    # @param [Array<Array>] triangles Each triangle is an Array of three
    #   vertices followed by a value that is passed through. A vertex is an
    #   Array of six Floats: the position followed by the normal.
    # @param [Boolean] convex
    # @param [Float, nil] segment_angle
    # @param [Boolean] flat Whether the normals follow the straight segments
    #   instead of the circle. It only applies with a segment angle.
    # @return [Array<Array(Array<Geom::Point3d>, Array<Geom::Vector3d>, Object)>]
    #   The points, the normals and the passed through value of each triangle.
    #   The points are counter-clockwise when seen from the side the normals
    #   point to.
    def project_triangles(triangles, convex, segment_angle = nil, flat: false)
      mirror = convex ? [1.0, -1.0] : [-1.0, 1.0]
      triangles.map { |triangle|
        mid_angle = segment_angle && segment_mid_angle(triangle, convex, segment_angle)
        flat_angle = flat ? mid_angle : nil
        points = []
        normals = []
        triangle[0, 3].each { |vertex|
          x, y, z, nx, ny, nz = vertex
          angle = mirror[0] * x / radius
          distance = radius + (mirror[1] * y)
          points << polar_point(angle, distance, z, mid_angle, segment_angle)
          # A normal stays perpendicular to its face when the part of it that
          # is along the circle is divided by how much the projection
          # stretches lengths in that direction.
          along = mirror[0] * nx * radius / nonzero(distance)
          outwards = mirror[1] * ny
          if flat_angle
            # On a straight segment a face along the segment faces the way the
            # middle of the segment does, and a face across it still faces
            # along the circle.
            cosine = nonzero(Math.cos(segment_angle / 2.0))
            along *= Math.cos(angle - flat_angle) / cosine
            outwards /= cosine
          end
          normals << polar_normal(angle, flat_angle || angle, along, outwards, nz)
        }
        wind_by_normals(points, normals)
        [points, normals, triangle[3]]
      }
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

    # @param [Array<Array>] triangle
    # @param [Boolean] convex
    # @param [Float] segment_angle
    # @return [Float] The angle of the middle of the segment the triangle is
    #   in.
    def segment_mid_angle(triangle, convex, segment_angle)
      x = (triangle[0][0] + triangle[1][0] + triangle[2][0]) / 3.0
      angle = (convex ? x : -x) / radius
      segment = (angle / segment_angle).to_i
      segment_angle * (segment + (convex ? 0.5 : -0.5))
    end

    # @param [Float] angle
    # @param [Float] distance The distance from the origin of a point on the
    #   circle at that angle.
    # @param [Float] z
    # @param [Float, nil] mid_angle The angle of the middle of the straight
    #   segment the point is moved onto, if any.
    # @param [Float, nil] segment_angle
    # @return [Geom::Point3d]
    def polar_point(angle, distance, z, mid_angle, segment_angle)
      if mid_angle
        # The segment is the chord between two points on the circle. The middle
        # of the chord is the point of it that is closest to the origin.
        distance *= Math.cos(segment_angle / 2.0) / nonzero(Math.cos(angle - mid_angle))
      end
      point = Geom::Point3d.new(distance * Math.cos(angle), distance * Math.sin(angle), z)
      @transformation ? point.transform(@transformation) : point
    end

    # @param [Float] along_angle The angle around the circle at which `along`
    #   is in the direction of the circle.
    # @param [Float] outwards_angle The angle around the circle that
    #   `outwards` points out of the circle at.
    # @param [Float] along
    # @param [Float] outwards
    # @param [Float] z
    # @return [Geom::Vector3d] A unit vector.
    def polar_normal(along_angle, outwards_angle, along, outwards, z)
      x = (Math.cos(outwards_angle) * outwards) - (Math.sin(along_angle) * along)
      y = (Math.sin(outwards_angle) * outwards) + (Math.cos(along_angle) * along)
      normal = Geom::Vector3d.new(x, y, z)
      normal.transform!(@transformation) if @transformation
      normal.normalize! if normal.valid?
      normal
    end

    # @param [Float] value
    # @return [Float] The value, moved away from zero if it is too close to
    #   divide by.
    def nonzero(value)
      return value if value.abs > 1.0e-9

      value < 0.0 ? -1.0e-9 : 1.0e-9
    end

    # Reorders the vertices of a triangle so that they are counter-clockwise
    # when seen from the side the normals point to.
    #
    # @param [Array<Geom::Point3d>] points
    # @param [Array<Geom::Vector3d>] normals
    def wind_by_normals(points, normals)
      face_normal = (points[1] - points[0]) * (points[2] - points[0])
      return if face_normal % normals[0] >= 0.0

      points[1], points[2] = points[2], points[1]
      normals[1], normals[2] = normals[2], normals[1]
    end

  end
end # module
