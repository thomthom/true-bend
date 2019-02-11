require 'tt_truebend/constants/view'
require 'tt_truebend/gl/bender_drawer'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/gl/drawing_helper'
require 'tt_truebend/gl/grid'
require 'tt_truebend/gl/slicer'
require 'tt_truebend/gl/subdivided_segment'
require 'tt_truebend/helpers/edge'
require 'tt_truebend/helpers/instance'
require 'tt_truebend/geom/polar_projection'
require 'tt_truebend/geom/segment'
require 'tt_truebend/app_settings'

module TT::Plugins::TrueBend
  class Bender

    include BenderDrawer
    include DrawingHelper
    include EdgeHelper
    include InstanceHelper
    include ViewConstants

    attr_reader :segment, :direction
    attr_accessor :segmented, :soft_smooth

    TAU = Math::PI * 2

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
      # Toggles whether to soften & smooth the edges created to subdivide the
      # mesh for the bending.
      @soft_smooth = true

      # Grid widget to visualize the how the bend geometry is mapped from its
      # original shape to the bent shape. `@grid` represent the original mesh.
      bounds = definition(instance).bounds
      offset = Geom::Transformation.new(bounds.min)
      @grid = Grid.new(bounds.width, bounds.height)
      @grid.x_subdivs = @segmenter.subdivisions
      @grid.transformation = instance.transformation * offset
    end

    # @return [nil]
    def reset
      @direction = Geom::Vector3d.new(0, 0, 0)
      @angle = 0.0
      nil
    end

    def bending?
      @angle.abs > 0.0 # TODO: Tolerance?
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
      @direction = direction.clone
      if @direction.valid?
        @direction.length = [max_bend_distance, direction.length].min
      end
      # The segment length is the circumference of max bend (360 degrees).
      # Take this circumference and use the ratio of the
      # bend distance (direction.length) and use it as a ratio of the max bend.
      # That ratio will then give us the bend angle.
      ratio = @direction.length / max_bend_distance
      @angle = TAU * ratio
      nil
    end

    # @return [Sketchup::ComponentInstance, Sketchup::Group]
    def commit
      instance = ensure_groups_are_uniqe(@instance)
      entities = definition(instance).entities

      explode_curves(entities)

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
    def max_bend_distance
      circumference = segment.length
      circle_radius = circumference / TAU
      circle_radius * 2.0
    end

    # @return [Length]
    def distance
      ratio = @angle / TAU
      (max_bend_distance * ratio).to_l
    end

    # @param [Length] value
    def distance=(value)
      # TODO: Revise what "distance" represent.
      # If bend has been reset to zero, use the normal instead.
      # Might be better to keep direction and length separately.
      vector = direction.valid? ? direction.clone : @normal.clone
      vector.length = value
      bend(vector)
    end

    # @return [Float]
    def angle # rubocop:disable Style/TrivialAccessors
      # radians = length / radius
      @angle
    end

    # @param [Float] value Angle in radians.
    def angle=(value) # rubocop:disable Style/TrivialAccessors
      # TODO: Update direction length?
      @angle = value
    end

    # @return [Length]
    def radius
      (@segment.length / angle).to_l
    end

    # @return [Length]
    def diameter
      (radius * 2.0).to_l
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
      else # rubocop:disable Style/EmptyElse
        nil
      end
    end

    # @param [Sketchup::View] view
    def draw(view)
      # Reference segment
      @segmenter.draw(view)

      # Projected reference segment
      polar_points = bend_points(@segmenter.points)
      draw_projected_reference_segment(view, polar_points, @segmenter.line_width)

      # Reference grid
      view.drawing_color = 'green'
      @grid.draw(view)

      # No need to draw anything else unless there is a bend.
      # return unless @direction.valid?
      return unless bending?

      # Set up the projection.
      x_axis = origin.vector_to(polar_points.last)
      projection = PolarProjection.new(radius)
      projection.axes(origin, x_axis)

      # Projected grid
      draw_projected_grid(view, @instance, projection, @segmenter, convex?)

      # Projected mesh
      planes = slicing_planes(@segmenter)
      mesh_points = slice_mesh(@instance, planes)
      bent_mesh = bend_mesh(mesh_points, projection, convex?, segment_angle)

      draw_mesh(view, bent_mesh, 'maroon')

      draw_debug_global_mesh(view, mesh_points)
      draw_debug_local_mesh(view, mesh_points, @instance.transformation.inverse)
      draw_debug_planes(view, planes, world_to_segment_space)

      # Bend information
      length = curve_length(polar_points)
      degrees = Sketchup.format_angle(angle)
      segment_mid_point = @segmenter.segment.mid_point
      draw_bend_info(view, polar_points, [origin, segment_mid_point], degrees)
      draw_sagitta(view, [origin, segment_mid_point], polar_points, sagitta)
      draw_debug_bend_info(view, polar_points, length, arc_length, @segment)

      view.tooltip = "Angle: #{degrees}\n"\
                     "Radius: #{radius}\n"\
                     "Bend: #{distance}"
    end

    private

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Array<Array(Geom::Point3d, Geom::Vector3d)>] planes
    # @return [Array<Geom::Point3d>]
    def slice_mesh(instance, planes)
      slicer = Slicer.new(planes)
      entities = definition(instance).entities
      slicer.segment_points(entities, instance.transformation)
    end

    # @param [Array<Geom::Point3d>] mesh_points
    # @param [Projection] projection
    # @param [Boolean] is_convex
    # @param [Float] segment_angle
    # @return [Array<Geom::Point3d>]
    def bend_mesh(mesh_points, projection, is_convex, segment_angle)
      # Polar project must be done in a coordinate system local to the
      # reference segment.
      tr_to_segment_space = world_to_segment_space
      polar_mesh_points = mesh_points.map { |point|
        point.transform(tr_to_segment_space)
      }
      projection.project(polar_mesh_points, is_convex, segment_angle)
    end

    # @param [Sketchup::Entities] entities
    # @param [Geom::Transformation] transformation
    # @return [nil]
    def transform_polar(entities, transformation)
      # http://sketchup.thomthom.net/extensions/TT_TrueBend/reports/report/24606?version=1.0.1
      return nil unless polar_x_axis.valid?

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
        transform_polar(definition(entity).entities, tr)
      }
      nil
    end

    # Create slicing planes which are perpendicular to the reference segment.
    #
    # @param [SubdividedSegmentWidget] segmenter
    # @return [Array<Array(Geom::Point3d, Geom::Vector3d)>]
    def slicing_planes(segmenter)
      plane_normal = segmenter.segment.line[1]
      segmenter.points.map { |point|
        [point.clone, plane_normal.clone]
      }
    end

    # Creates a transformation that convert world coordinates to a local
    # coordinate for the reference segment.
    #
    # @return [Geom::Transformation]
    def world_to_segment_space
      # TODO: Will the direction of the segment matter? Does it need to be
      #       sorted somehow?
      @segment.transformation.inverse
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
        return arc(o, x, z, radius, a1, a2, @segmenter.subdivisions) if x.valid?
      end
      points
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
