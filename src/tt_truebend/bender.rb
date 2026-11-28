require 'tt_truebend/constants/view'
require 'tt_truebend/gl/bender_drawer'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/gl/drawing_helper'
require 'tt_truebend/gl/face_colors'
require 'tt_truebend/gl/face_drawer'
require 'tt_truebend/gl/face_triangulator'
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
    include FaceDrawer
    include InstanceHelper
    include ViewConstants

    attr_reader :segment, :direction
    attr_accessor :segmented, :soft_smooth

    TAU = Math::PI * 2

    # The sagitta of a bend increases with the angle up to this angle, in
    # radians, and decreases beyond it. It is the solution of
    # tan(angle / 4) = angle / 2 within a full circle.
    MAX_SAGITTA_ANGLE = 4.662244740828845

    # The bounds of the bent instance are found by bending the bounding box of
    # the instance. The box is divided into this many slices of equal length
    # along the reference segment, and the corners of the slices are bent.
    BOUNDS_SLICES = 48

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
      @grid = create_grid
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
      @grid.x_subdivs = value
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

    # Copies the angle and the bend side (concave or convex) of another bender.
    #
    # @param [Bender] other
    # @return [nil]
    def match_angle(other)
      return reset unless other.bending? && other.can_bend?

      @direction = other.concave? ? @normal.clone : @normal.reverse
      @direction.length = max_bend_distance * (other.angle.abs / TAU)
      @angle = other.angle
      nil
    end

    # Copies the distance and the bend side (concave or convex) of another
    # bender. The bend is clamped to a full circle.
    #
    # @param [Bender] other
    # @return [nil]
    def match_distance(other)
      return reset unless other.bending? && other.can_bend?

      direction = other.concave? ? @normal.clone : @normal.reverse
      direction.length = other.distance.abs
      bend(direction)
    end

    # Copies the radius and the bend side (concave or convex) of another bender.
    # The bend is clamped to a full circle.
    #
    # @param [Bender] other
    # @return [nil]
    def match_radius(other)
      return reset unless other.bending? && other.can_bend?

      @direction = other.concave? ? @normal.clone : @normal.reverse
      self.radius = other.radius.to_f.abs
      nil
    end

    # Copies the sagitta and the bend side (concave or convex) of another
    # bender. The sagitta is clamped to {#max_sagitta}.
    #
    # @param [Bender] other
    # @return [nil]
    def match_sagitta(other)
      # Beyond this angle, setting the sagitta would give a smaller angle with
      # the same sagitta.
      return match_angle(other) if other.angle.abs > MAX_SAGITTA_ANGLE
      return reset unless other.bending? && other.can_bend?

      @direction = other.concave? ? @normal.clone : @normal.reverse
      self.sagitta = other.sagitta.to_f.abs
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

    # A negative radius flips the bend direction. The bend is clamped to a full
    # circle.
    #
    # @param [Length] value
    def radius=(value)
      # The arc length is preserved: length = radius * angle
      angle = [@segment.length / value.to_f.abs, TAU].min
      distance = max_bend_distance * (angle / TAU)
      self.distance = value < 0 ? -distance : distance
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
      sagitta_for(angle).to_l
    end

    # A negative sagitta flips the bend direction. Two angles can have the same
    # sagitta, and the smaller one is used. The sagitta is clamped to
    # {#max_sagitta}.
    #
    # @param [Length] value
    def sagitta=(value)
      angle = angle_for_sagitta(value.to_f.abs)
      if angle.zero?
        # A distance of zero would lose the side the bend is on.
        self.angle = 0.0
      else
        distance = max_bend_distance * (angle / TAU)
        self.distance = value < 0 ? -distance : distance
      end
    end

    # @return [Length] The largest sagitta the bend can have.
    def max_sagitta
      sagitta_for(MAX_SAGITTA_ANGLE).to_l
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
      bounds.add(bent_bounds) if bending?
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

      projection = polar_projection

      # Projected grid
      grid_points = bend_mesh(@grid.segment_points, projection, convex?, nil)
      draw_projected_grid(view, grid_points)

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
                     "Bend: #{distance}\n"\
                     "Sagitta: #{sagitta.abs.to_l}"
    end

    # Draws the faces of the instance the way the bend would leave them. Call
    # it after everything else that is drawn in model space, because anything
    # drawn afterwards is hidden where it is behind the faces.
    #
    # @param [Sketchup::View] view
    def draw_faces(view)
      return unless bending? && FaceDrawer.supported?

      face_colors = FaceColors.new(view.model, SETTINGS.debug_face_opacity)
      return unless face_colors.fill?

      triangles = bent_triangles(face_colors)
      draw_triangles(view, triangles, SETTINGS.debug_draw_see_through_faces?)
    end

    # Triangulates the visible faces of the instance and bends the triangles
    # the way the bend would bend the faces.
    #
    # @param [FaceColors] face_colors
    # @return [Array<PreviewTriangle>]
    def bent_triangles(face_colors)
      to_segment_space = world_to_segment_space
      # The bend slices the instance where the reference segment is
      # subdivided.
      slicing_plane_positions = @segmenter.points.map { |point|
        point.transform(to_segment_space).x
      }.sort
      triangulator = FaceTriangulator.new(face_colors)
      triangles = triangulator.triangles(@instance, to_segment_space)
      triangles = triangulator.slice(triangles, slicing_plane_positions)
      # A bend that is not segmented has no segment angle, and is always
      # smooth.
      polar_projection.project_triangles(triangles, convex?, segment_angle, smooth: @soft_smooth)
    end

    private

    # @param [Float] angle Angle in radians.
    # @return [Float] The sagitta of a bend by the given angle.
    def sagitta_for(angle)
      return 0.0 if angle.zero?

      # https://en.wikipedia.org/wiki/Circular_segment
      # h = R(1 - cos(a/2)), where 1 - cos(a/2) = 2 * sin(a/4)^2. The latter
      # keeps its precision for small angles. Dividing by the angle last avoids
      # an infinite radius for the smallest angles.
      @segment.length * 2.0 * (Math.sin(angle / 4.0)**2) / angle
    end

    # @param [Float] sagitta A sagitta that is not negative.
    # @return [Float] The smallest angle, in radians, that gives the sagitta,
    #   or `MAX_SAGITTA_ANGLE` when no angle does.
    def angle_for_sagitta(sagitta)
      # The angle has no closed-form solution. The sagitta increases with the
      # angle over the whole range, which a binary search requires.
      range = 0.0..MAX_SAGITTA_ANGLE
      range.bsearch { |angle| sagitta_for(angle) >= sagitta } || MAX_SAGITTA_ANGLE
    end

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Array<Array(Geom::Point3d, Geom::Vector3d)>] planes
    # @return [Array<Geom::Point3d>]
    def slice_mesh(instance, planes)
      slicer = Slicer.new(planes)
      entities = definition(instance).entities
      slicer.segment_points(entities, instance.transformation)
    end

    # @param [Array<Geom::Point3d>] mesh_points
    # @param [PolarProjection] projection
    # @param [Boolean] is_convex
    # @param [Float, nil] segment_angle
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
      projected_points = polar_projection.project(mesh_points, convex?, segment_angle)

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

    # The axes of the coordinate system the bend is computed in.
    #
    # X runs along the reference segment, Y points away from the concave side
    # of the bend and Z is the axis the geometry is bent around.
    #
    # @return [Array(Geom::Vector3d, Geom::Vector3d, Geom::Vector3d)]
    def segment_axes
      x_axis = @segment.direction.normalize
      z_axis = (x_axis * @normal.reverse).normalize
      y_axis = z_axis * x_axis
      [x_axis, y_axis, z_axis]
    end

    # Creates a grid covering the extents of the instance, in the plane of the
    # bend, with its X direction running along the reference segment.
    #
    # @return [Grid]
    def create_grid
      to_world = world_to_segment_space.inverse
      to_segment_space = world_to_segment_space * @instance.transformation
      bounds = definition(@instance).bounds
      corners = Array.new(8) { |i| bounds.corner(i).transform(to_segment_space) }
      y_min, y_max = corners.map(&:y).minmax
      z_min = corners.map(&:z).min
      offset = Geom::Transformation.new(Geom::Point3d.new(0, y_min, z_min))
      grid = Grid.new(@segment.length, y_max - y_min)
      grid.x_subdivs = subdivisions
      grid.transformation = to_world * offset
      grid
    end

    # Bounds that enclose the instance the way the bend would leave it. They
    # are those of the bent bounding box of the instance, so they can be larger
    # than the bent geometry.
    #
    # @return [Geom::BoundingBox]
    def bent_bounds
      to_segment_space = world_to_segment_space * @instance.transformation
      box = definition(@instance).bounds
      box_corners = Array.new(8) { |index| box.corner(index).transform(to_segment_space) }
      x_min, x_max = box_corners.map(&:x).minmax
      y_min_max = box_corners.map(&:y).minmax
      z_min_max = box_corners.map(&:z).minmax
      slice_length = (x_max - x_min).to_f / BOUNDS_SLICES
      slice_corners = (0..BOUNDS_SLICES).flat_map { |index|
        x = x_min + (slice_length * index)
        y_min_max.product(z_min_max).map { |y, z| Geom::Point3d.new(x, y, z) }
      }
      bounds = Geom::BoundingBox.new
      bounds.add(polar_projection.project(slice_corners, convex?, nil))
      # Between the corners of a slice the bend is an arc. The arc bulges
      # beyond the chord between the bent corners by its sagitta, which is
      # largest for the arc that is furthest from the origin of the bend.
      # The radius is negative when the angle is.
      outer_radius = radius.to_f.abs + y_min_max.map(&:abs).max
      slice_angle = slice_length / radius.to_f
      sagitta = outer_radius * (1.0 - Math.cos(slice_angle / 2.0))
      margin = Geom::Vector3d.new(sagitta, sagitta, sagitta)
      bounds.add(bounds.min - margin, bounds.max + margin)
    end

    # Creates a transformation that convert world coordinates to a local
    # coordinate for the reference segment.
    #
    # @return [Geom::Transformation]
    def world_to_segment_space
      Geom::Transformation.axes(@segment.start, *segment_axes).inverse
    end

    # @return [PolarProjection]
    def polar_projection
      projection = PolarProjection.new(radius)
      projection.axes(origin, polar_x_axis, segment_axes.z)
      projection
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
    # @param [Float] radius
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

    # @param [Array<Geom::Point3d>] points
    # @return [Length]
    def curve_length(points)
      total = 0.0
      (0...(points.size - 1)).each { |i|
        total += points[i].distance(points[i + 1])
      }
      total.to_l
    end

  end # class
end # module
