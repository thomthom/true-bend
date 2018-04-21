require 'tt_truebend/constants/view'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/gl/drawing_helper'
require 'tt_truebend/gl/grid'
require 'tt_truebend/gl/slicer'
require 'tt_truebend/gl/subdivided_segment'
require 'tt_truebend/helpers/edge'
require 'tt_truebend/geom/polar_projection'
require 'tt_truebend/geom/segment'

module TT::Plugins::TrueBend
  class Bender

    include DrawingHelper
    include EdgeHelper
    include ViewConstants

    attr_reader :segment, :direction
    attr_accessor :segmented, :soft_smooth

    # @param [Sketchup::ComponentInstance] instance
    # @param [Segment] segment
    # @param [Geom::Vector3d] normal
    def initialize(instance, segment, normal)
      # The instance to bend.
      @instance = instance
      # The normal (unit vector) for the concave direction of a bend.
      @normal = normal
      # The direction in which the bend is made. It's length determine magnitude
      # and its direction in relationship to @normal indicate concave or convex
      # bending.
      @direction = Geom::Vector3d.new(0, 0, 0)
      # The angle of the bend, in radians.
      @angle = 0.0
      # The reference segment which is used to compute the bending from.
      @segment = segment
      # Viewport widget that visualize the reference segment with points along
      # its length illustrating the current number of subdivisions.
      @segmenter = SubdividedSegmentWidget.new(segment, color: 'green')
      @segmenter.subdivisions = 24
      # Toggles whether the bend adhere to true curve or segmented curve.
      @segmented = true
      # Toogles whether to soften & smooth the edges created to subdivide the
      # mesh for the bending.
      @soft_smooth = true

      # Grid widget to visualize the how the bend geometry is mapped from its
      # original shape to the bent shape. `@grid` represent the original mesh.
      bounds = instance.definition.bounds
      @grid = Grid.new(bounds.width, bounds.height)
      @grid.x_subdivs = @segmenter.subdivisions
      @grid.transformation = instance.transformation
    end

    def reset
      @direction = Geom::Vector3d.new(0, 0, 0)
      @angle = 0.0
    end

    def can_bend?
      @direction.valid?
    end

    def concave?
      @direction.samedirection?(@normal)
    end

    def convex?
      !concave?
    end

    def subdivisions
      @segmenter.subdivisions
    end

    def subdivisions=(value)
      @segmenter.subdivisions = value
    end

    # @param [Geom::Vector3d] direction
    def bend(direction)
      @direction = direction
      @direction.length = segment.length if @direction.length > segment.length
      @angle = Math::PI * (@direction.length / segment.length * 2)
    end

    def commit
      instance = @instance.make_unique # TODO: Only if it's a group?
      instance_entities = instance.definition.entities

      # Because the instance might not be scaled uniformly the scaling must
      # be applied to the definition in order to correctly slice it.
      apply_instance_scaling(instance)

      # Slice the mesh.
      slicer = Slicer.new(@instance)
      plane_normal = @segment.line[1]
      @segmenter.points.each { |point|
        slicer.add_plane([point.clone, plane_normal])
      }
      slicer.slice { |new_edge|
        next if @segmented && !@soft_smooth
        new_edge.soft = true
        new_edge.smooth = true
        new_edge.casts_shadows = false
      }

      # Collect all vertices and create a 1:1 array mapping their positions.
      edges = instance_entities.grep(Sketchup::Edge)
      vertices = edges.map(&:vertices).flatten.uniq
      mesh_points = vertices.map(&:position)

      # Create a new set of points representing the polar projection.
      to_local = instance.transformation.inverse
      local_origin = origin.transform(to_local)
      local_polar_x_axis = polar_x_axis.transform(to_local)
      projection = PolarProjection.new(radius)
      projection.axes(local_origin, local_polar_x_axis)
      projected_points = projection.project(mesh_points, convex?, segment_angle)

      # Transform each vertex to their new position.
      vectors = vertices.each_with_index.map { |vertex, index|
        vertex.position.vector_to(projected_points[index])
      }
      smooth_new_edges(instance_entities) {
        instance_entities.transform_by_vectors(vertices, vectors)
      }

      # TODO: Bend child instances.

      instance
    end

    def distance
      (radius * (1 - Math.cos(angle / 2))).to_l
    end

    def distance=(value)
      # TODO: Revise what "distance" represent.
      vector = direction.clone
      vector.length = value
      bend(vector)
    end

    def angle
      # radians = length / radius
      @angle
    end

    def angle=(value)
      # TODO: Update direction length?
      @angle = value
    end

    def radius
      (@segment.length / angle).to_l
    end

    def chord
      # http://mathworld.wolfram.com/CircularSegment.html
      (2 * radius * Math.sin(0.5 * angle)).to_l
    end

    def sagitta
      # Compute the arc segment sagitta (distance).
      # https://en.wikipedia.org/wiki/Circular_segment
      # h = R(1 - cos(a/2))
      #     R - sqrt(R^2 - (c^2/4))
      (radius * (1 - Math.cos(angle / 2))).to_l
    end

    def arc_length
      # s = R * a
      (radius * angle).to_l
    end

    def polar_x_axis
      polar_points = bend_points(@segmenter.points)
      origin.vector_to(polar_points.last)
    end

    def bounds
      bounds = Geom::BoundingBox.new
      bounds.add(@segmenter.bounds)
      bounds
    end

    def origin
      if @direction.valid?
        @segment.mid_point.offset(@direction, radius)
      else
        @segment.mid_point.clone
      end
    end

    def segment_angle
      if @segmented
        angle / @segmenter.subdivisions.to_f
      else
        nil
      end
    end

    def draw(view)
      # Reference segment
      @segmenter.draw(view)

      # Projected reference segment
      polar_points = bend_points(@segmenter.points)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = @segmenter.line_width
      view.drawing_color = 'red'
      view.draw(GL_LINE_STRIP, polar_points)
      view.draw_points(polar_points, 6, DRAW_FILLED_SQUARE, 'red')

      # Reference grid
      view.drawing_color = 'green'
      @grid.draw(view)

      # Projected grid
      if @direction.valid?
        # Grid
        bounds = BoundingBoxWidget.new(@instance)
        grid = Grid.new(bounds.width, bounds.height)
        grid.x_subdivs = @segmenter.subdivisions

        x_axis = origin.vector_to(polar_points.last)
        projection = PolarProjection.new(radius)
        projection.axes(origin, x_axis)
        arc_grid = projection.project(grid.segment_points, convex?)

        view.line_stipple = STIPPLE_LONG_DASH
        view.line_width = 1
        view.drawing_color = 'red'
        view.draw(GL_LINES, lift(view, arc_grid))

        # Mesh
        to_scaled = bounds.scaling_transformation
        to_local = @instance.transformation.inverse
        to_polar = to_scaled * to_local
        plane_normal = @segment.line[1].transform(to_polar)
        slicer = Slicer.new(@instance)
        slicer.transformation = to_scaled
        @segmenter.points.each { |point|
          plane_origin = point.transform(to_polar)
          plane = [plane_origin, plane_normal]
          slicer.add_plane(plane)
        }
        mesh_points = slicer.segment_points
        bent_mesh = projection.project(mesh_points, convex?, segment_angle)
        view.line_stipple = STIPPLE_SOLID
        view.line_width = 2
        view.drawing_color = 'maroon'
        view.draw(GL_LINES, bent_mesh)
        view.draw_points(bent_mesh, 6, DRAW_FILLED_SQUARE, 'maroon')
        # slicer.draw(view)
      end

      # Debug

      if @direction.valid?
        # Information
        length = curve_length(polar_points)
        degrees = Sketchup.format_angle(angle)
        view.tooltip = "Radius: #{radius}\nAngle: #{degrees}\nLength: #{@segment.length} (#{length})"

        options = {
          font: 'Arial',
          size: 10,
          bold: true,
          color: 'purple'
        }

        mid = @segmenter.segment.mid_point

        # Radius segment
        view.line_stipple = STIPPLE_SOLID
        view.line_width = 1
        view.draw_points([mid, origin], 6, DRAW_CROSS, 'purple')

        view.line_stipple = STIPPLE_SHORT_DASH
        view.drawing_color = 'purple'
        view.draw(GL_LINES, [mid, origin])

        # Pie end segments
        view.drawing_color = 'purple'
        view.line_stipple = STIPPLE_LONG_DASH
        view.line_width = 2
        view.draw(GL_LINES, [origin, polar_points.first])
        view.line_width = 1
        view.draw(GL_LINES, [origin, polar_points.last])

        # Radius
        pt = view.screen_coords(Segment.new(mid, origin).mid_point)
        view.draw_text(pt, radius.to_s, options)

        # Angle
        v1 = origin.vector_to(polar_points.first)
        v2 = origin.vector_to(polar_points.last)
        a = full_angle_between(v1, v2)
        fa = Sketchup.format_angle(a)
        pt = view.screen_coords(origin)
        view.draw_text(pt, "#{fa}° (#{degrees}°)", options)

        # Curve Length
        pt = view.screen_coords(polar_points.first)
        options[:color] = 'red'
        view.draw_text(pt, "#{length} (#{arc_length})", options)

        # Segment Length
        pt = view.screen_coords(@segment.points.last)
        options[:color] = 'green'
        view.draw_text(pt, @segment.length.to_s, options)
      end
    end

    private

    # Return the full orientation of the two lines. Going counter-clockwise.
    #
    # @return [Float]
    def full_angle_between(vector1, vector2, normal = Z_AXIS)
      direction = (vector1 * vector2) % normal
      angle = vector1.angle_between(vector2)
      angle = 360.degrees - angle if direction < 0.0
      angle
    end

    # Creates a set of `Geom::Point3d` objects for an arc.
    #
    # @param [Geom::Point3d] center
    # @param [Geom::Vector3d] xaxis
    # @param [Geom::Vector3d] normal
    # @param [Number] radius
    # @param [Float] start_angle in radians
    # @param [Float] end_angle in radians
    # @param [Integer] num_segments
    #
    # @return [Array<Geom::Point3d>]
    def arc(center, xaxis, normal, radius, start_angle, end_angle, num_segments = 12)
      # Generate the first point.
      t = Geom::Transformation.rotation(center, normal, start_angle)
      points = []
      points << center.offset(xaxis, radius).transform(t)
      # Prepare a transformation we can repeat on the last entry in point to complete the arc.
      t = Geom::Transformation.rotation(center, normal, (end_angle - start_angle) / num_segments)
      1.upto(num_segments) {
        points << points.last.transform(t)
      }
      points
    rescue StandardError
      p [center, xaxis, normal, radius, start_angle, end_angle, num_segments]
      raise
    end

    def bend_points(points)
      o = origin
      u = o.vector_to(points.first)
      v = o.vector_to(points.last)
      z = u * v
      if u.valid? && z.valid?
        a2 = angle / 2.0
        a1 = -a2
        x = o.vector_to(Segment.new(points.first, points.last).mid_point)
        arc(o, x, z, radius, a1, a2, @segmenter.subdivisions)
      else
        points
      end
    end

    def curve_length(points)
      total = 0.0
      (0...points.size - 1).each { |i|
        total += points[i].distance(points[i + 1])
      }
      total.to_l
    end

    def apply_instance_scaling(instance)
      bounds = BoundingBoxWidget.new(instance)
      to_scaled = bounds.scaling_transformation
      instance.definition.entities.transform_entities(
        to_scaled,
        instance.definition.entities.to_a
      )
      to_world = instance.transformation
      to_local = instance.transformation.inverse
      instance.transform!(to_world * to_scaled.inverse * to_local)
      to_scaled
    end

  end # class
end # module
