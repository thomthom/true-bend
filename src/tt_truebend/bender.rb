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

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Segment] segment The reference segment for the bend.
    # @param [Geom::Vector3d] normal The direction in which the bend is made.
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

    # @return [nil]
    def reset
      @direction = Geom::Vector3d.new(0, 0, 0)
      @angle = 0.0
      nil
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

    # @return [Integer]
    def subdivisions
      @segmenter.subdivisions
    end

    # @param [Integer] value
    def subdivisions=(value)
      @segmenter.subdivisions = value
    end

    # @param [Geom::Vector3d] direction
    # @return [nil]
    def bend(direction)
      @direction = direction
      @direction.length = segment.length if @direction.length > segment.length
      @angle = Math::PI * (@direction.length / segment.length * 2)
      nil
    end

    # @return [Sketchup::ComponentInstance, Sketchup::Group]
    def commit
      instance = ensure_groups_are_uniqe(@instance)
      entities = instance.definition.entities

      planes = slicing_planes(@segmenter)

      slicer = Slicer.new(planes)
      slicer.slice(instance) { |new_edge|
        next if @segmented && !@soft_smooth
        new_edge.soft = true
        new_edge.smooth = true
        new_edge.casts_shadows = false
      }

      transform_polar(entities, instance.transformation)

      instance
    end

    # @return [Length]
    def distance
      (radius * (1 - Math.cos(angle / 2))).to_l
    end

    # @param [Length] value
    def distance=(value)
      # TODO: Revise what "distance" represent.
      vector = direction.clone
      vector.length = value
      bend(vector)
    end

    # @return [Float]
    def angle
      # radians = length / radius
      @angle
    end

    # @param [Float] value Angle in radians.
    def angle=(value)
      # TODO: Update direction length?
      @angle = value
    end

    # @return [Length]
    def radius
      (@segment.length / angle).to_l
    end

    # @return [Length]
    def chord
      # http://mathworld.wolfram.com/CircularSegment.html
      (2 * radius * Math.sin(0.5 * angle)).to_l
    end

    # @return [Length]
    def sagitta
      # Compute the arc segment sagitta (distance).
      # https://en.wikipedia.org/wiki/Circular_segment
      # h = R(1 - cos(a/2))
      #     R - sqrt(R^2 - (c^2/4))
      (radius * (1 - Math.cos(angle / 2))).to_l
    end

    # @return [Length]
    def arc_length
      # s = R * a
      (radius * angle).to_l
    end

    # @return [Geom::Vector3d]
    def polar_x_axis
      polar_points = bend_points(@segmenter.points)
      origin.vector_to(polar_points.last)
    end

    # @return [Geom::BoundingBox]
    def bounds
      bounds = Geom::BoundingBox.new
      bounds.add(@segmenter.bounds)
      bounds
    end

    # @return [Geom::Point3d]
    def origin
      if @direction.valid?
        @segment.mid_point.offset(@direction, radius)
      else
        @segment.mid_point.clone
      end
    end

    # @return [Float, nil]
    def segment_angle
      if @segmented
        angle / @segmenter.subdivisions.to_f
      else
        nil
      end
    end

    # @param [Sketchup::View] view
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
        planes = slicing_planes(@segmenter)
        slicer = Slicer.new(planes)
        entities = @instance.definition.entities
        mesh_points = slicer.segment_points(entities, @instance.transformation)

        # Polar project must be done in a cooridinate system local to the
        # reference segment.
        tr_to_segment_space = world_to_segment_space

        # Global Mesh
        # view.line_stipple = STIPPLE_SOLID
        # view.line_width = 2
        # view.drawing_color = 'orange'
        # view.draw(GL_LINES, mesh_points)
        # view.draw_points(mesh_points, 4, DRAW_FILLED_SQUARE, 'orange')

        # Local Mesh
        # local_mesh = mesh_points.map { |pt| pt.transform(tr) }
        # view.line_stipple = STIPPLE_SOLID
        # view.line_width = 2
        # view.drawing_color = 'purple'
        # view.draw(GL_LINES, local_mesh)
        # view.draw_points(local_mesh, 4, DRAW_FILLED_SQUARE, 'purple')

        # Global Bent Mesh
        polar_mesh_points = mesh_points.map { |pt|
          pt.transform(tr_to_segment_space)
        }
        bent_mesh = projection.project(polar_mesh_points, convex?, segment_angle)
        view.line_stipple = STIPPLE_SOLID
        view.line_width = 2
        view.drawing_color = 'maroon'
        view.draw(GL_LINES, bent_mesh)
        view.draw_points(bent_mesh, 4, DRAW_FILLED_SQUARE, 'maroon')
        # slicer.draw(view)

        # Slice Planes
        # planes.each { |plane|
        #   draw_plane(view, plane, 1.m, 'green')

        #   local_plane = plane.map { |n| n.transform(tr_to_segment_space) }
        #   draw_plane(view, local_plane, 1.m, 'red')
        # }
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

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @return [Sketchup::ComponentInstance, Sketchup::Group]
    def ensure_groups_are_uniqe(instance)
      if @instance.is_a?(Sketchup::Group)
        @instance.make_unique
      else
        @instance
      end
    end

    # TODO: Move to mix-in module.
    def instance?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d, Geom::Vector3d>] plane
    # @param [Numeric] size
    # @param [Sketchup::Color] color
    # @return [nil]
    # TODO: Move to drawing helper.
    def draw_plane(view, plane, size, color)
      color = Sketchup::Color.new(color)
      points = [
        Geom::Point3d.new(-0.5, -0.5, 0),
        Geom::Point3d.new( 0.5, -0.5, 0),
        Geom::Point3d.new( 0.5,  0.5, 0),
        Geom::Point3d.new(-0.5,  0.5, 0),
      ]
      tr_scale = Geom::Transformation.scaling(size)
      origin, z_axis = plane
      tr_axes = Geom::Transformation.new(origin, z_axis)
      tr = tr_axes * tr_scale
      points.each { |pt| pt.transform!(tr) }
      view.drawing_color = color
      view.line_stipple = STIPPLE_LONG_DASH
      view.line_width = 2
      view.draw(GL_LINE_LOOP, points)
      color.alpha = 0.1
      view.drawing_color = color
      view.draw(GL_QUADS, points)
      nil
    end

    # @param [Sketchup::Entities] entities
    # @param [Geom::Transformation] transformation
    # @return [nil]
    def transform_polar(entities, transformation)
      local_to_segment_space = world_to_segment_space * transformation

      # Collect all vertices and create a 1:1 array mapping their positions.
      edges = entities.grep(Sketchup::Edge)
      vertices = edges.map(&:vertices).flatten.uniq
      mesh_points = vertices.map { |vertex|
        vertex.position.transform(local_to_segment_space)
      }

      # Create a new set of points representing the polar projection.
      projection = PolarProjection.new(radius)
      projection.axes(origin, polar_x_axis)
      projected_points = projection.project(mesh_points, convex?, segment_angle)

      # Transform each vertex to their new position.
      to_local = transformation.inverse
      vectors = vertices.each_with_index.map { |vertex, index|
        vertex.position.vector_to(projected_points[index].transform(to_local))
      }
      smooth_new_edges(entities) {
        entities.transform_by_vectors(vertices, vectors)
      }

      # Recurse into child instances,
      entities.each { |entity|
        next unless instance?(entity)
        # Assumes instance is unique already.
        tr = transformation * entity.transformation
        project(entity.definition.entities, tr)
      }
      nil
    end

    # Create slicing planes which are perpendicular to the reference segment.
    #
    # @param [SubdividedSegmentWidget] segmenter
    # @return [Array<Array<Geom::Point3d, Geom::Vector3d>>]
    def slicing_planes(segmenter)
      plane_normal = segmenter.segment.line[1]
      planes = segmenter.points.map { |point|
        [point.clone, plane_normal.clone]
      }
    end

    # Creates a transformation that convert world coordinates to a local
    # coordinate for the reference segment.
    #
    # @return [Geom::Transformation]
    def world_to_segment_space
      # TODO: Segment.transformation
      # TODO: Will the direction of the segment matter? Does it need to be
      #       sorted somehow?
      segment_origin, x_axis = @segment.line
      y_axis = x_axis.axes.x
      z_axis = x_axis.axes.y
      Geom::Transformation.axes(segment_origin, x_axis, y_axis, z_axis).inverse
    end

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

    # @param [Array<Geom::Point3d>]
    # @return [Length]
    def curve_length(points)
      total = 0.0
      (0...points.size - 1).each { |i|
        total += points[i].distance(points[i + 1])
      }
      total.to_l
    end

  end # class
end # module
