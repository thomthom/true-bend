require 'tt_truebend/gl/preview_triangle'

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

    # Projects triangles the way {#project} projects points. The vertex
    # normals are transformed with the surface, so that they stay
    # perpendicular to it.
    #
    # @param [Array<PreviewTriangle>] triangles
    # @param [Boolean] convex
    # @param [Float, nil] segment_angle The angle that each straight segment
    #   of a segmented bend spans. Every triangle must be within one segment.
    # @param [Boolean] smooth Whether the normals follow the circle across the
    #   straight segments, which shades the segments as one curved surface.
    #   Otherwise each segment is shaded as the plane it is. Without a segment
    #   angle there are no segments, and the normals always follow the circle.
    # @return [Array<PreviewTriangle>] The vertices of each triangle are
    #   counter-clockwise when seen from the side their normals point to.
    def project_triangles(triangles, convex, segment_angle = nil, smooth: true)
      # Triangles share vertices, so a vertex is projected only once for each
      # chord it is on.
      projected_by_chord = Hash.new { |hash, chord_angle|
        hash[chord_angle] = {}.compare_by_identity
      }
      triangles.map { |triangle|
        chord_angle = segment_angle && chord_mid_angle(triangle, convex, segment_angle)
        projected = projected_by_chord[chord_angle]
        vertices = triangle.vertices.map { |vertex|
          projected[vertex] ||= project_vertex(vertex, convex, chord_angle, segment_angle, smooth)
        }
        vertices = counter_clockwise(vertices)
        PreviewTriangle.new(vertices, triangle.front_color, triangle.back_color)
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

    # A straight segment of a segmented bend is a chord of the circle. The
    # centroid of the triangle decides which chord the triangle is on.
    #
    # @param [PreviewTriangle] triangle
    # @param [Boolean] convex
    # @param [Float] segment_angle
    # @return [Float] The angle around the circle of the middle of the chord.
    def chord_mid_angle(triangle, convex, segment_angle)
      a, b, c = triangle.vertices
      centroid_x = (a.x + b.x + c.x) / 3.0
      angle = (convex ? centroid_x : -centroid_x) / radius
      segment_index = (angle / segment_angle).to_i
      segment_angle * (segment_index + (convex ? 0.5 : -0.5))
    end

    # @param [PreviewVertex] vertex
    # @param [Boolean] convex
    # @param [Float, nil] chord_angle The angle around the circle of the
    #   middle of the chord the vertex is moved onto, if any.
    # @param [Float, nil] segment_angle The angle the chord spans.
    # @param [Boolean] smooth See {#project_triangles}.
    # @return [PreviewVertex]
    def project_vertex(vertex, convex, chord_angle, segment_angle, smooth)
      # As in {#project}, a convex bend mirrors Y and a concave bend mirrors
      # X. X then runs counter-clockwise around the circle and Y away from its
      # origin, whichever way the bend curves.
      x_mirror = convex ? 1.0 : -1.0
      y_mirror = -x_mirror
      angle = x_mirror * vertex.x / radius
      distance = radius + (y_mirror * vertex.y)
      # Normals are transformed by the inverse transpose of the Jacobian of
      # the projection, which keeps them perpendicular to the surface. The
      # projection scales lengths along the circle by `distance / radius` and
      # leaves the other directions unchanged.
      tangential = x_mirror * vertex.normal_x * radius / nonzero(distance)
      radial = y_mirror * vertex.normal_y
      radial_angle = angle
      if chord_angle
        # The vertex is moved onto the chord along the line through the
        # origin. The middle of the chord is this many times as far from the
        # origin as its ends are.
        chord_distance_ratio = nonzero(Math.cos(segment_angle / 2.0))
        distance *= chord_distance_ratio / nonzero(Math.cos(angle - chord_angle))
        unless smooth
          # On a chord the projection maps X to the direction of the chord and
          # Y to the line from the origin through the vertex. The radial part
          # of the normal is then perpendicular to the chord, and the two
          # parts are scaled as follows.
          tangential *= Math.cos(angle - chord_angle) / chord_distance_ratio
          radial /= chord_distance_ratio
          radial_angle = chord_angle
        end
      end
      position = polar_point(angle, distance, vertex.z)
      normal = polar_normal(tangential, angle, radial, radial_angle, vertex.normal_z)
      PreviewVertex.from_geom(position, normal)
    end

    # @param [Float] angle The angle of the point around the circle.
    # @param [Float] distance The distance from the origin to the point.
    # @param [Float] z
    # @return [Geom::Point3d]
    def polar_point(angle, distance, z)
      point = Geom::Point3d.new(distance * Math.cos(angle), distance * Math.sin(angle), z)
      @transformation ? point.transform(@transformation) : point
    end

    # @param [Float] tangential The component of the normal along the circle.
    # @param [Float] tangential_angle The angle around the circle at which the
    #   tangential component is tangent to the circle.
    # @param [Float] radial The component of the normal away from the origin.
    # @param [Float] radial_angle The angle around the circle that the radial
    #   component points out of the circle at.
    # @param [Float] z
    # @return [Geom::Vector3d] A unit vector.
    def polar_normal(tangential, tangential_angle, radial, radial_angle, z)
      x = (radial * Math.cos(radial_angle)) - (tangential * Math.sin(tangential_angle))
      y = (radial * Math.sin(radial_angle)) + (tangential * Math.cos(tangential_angle))
      normal = Geom::Vector3d.new(x, y, z)
      normal.transform!(@transformation) if @transformation
      normal.normalize! if normal.valid?
      normal
    end

    # @param [Float] value
    # @return [Float] The value, or a value of the same sign that is safe to
    #   divide by if the value is too close to zero.
    def nonzero(value)
      return value if value.abs > 1.0e-9

      value < 0.0 ? -1.0e-9 : 1.0e-9
    end

    # @param [Array(PreviewVertex, PreviewVertex, PreviewVertex)] vertices
    # @return [Array(PreviewVertex, PreviewVertex, PreviewVertex)] The
    #   vertices in counter-clockwise order when seen from the side the normal
    #   of the first vertex points to.
    def counter_clockwise(vertices)
      a, b, c = vertices
      face_normal = (b.position - a.position) * (c.position - a.position)
      face_normal % a.normal < 0.0 ? [a, c, b] : vertices
    end

  end
end # module
