require 'tt_truebend/constants/view'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/gl/drawing_helper'
require 'tt_truebend/gl/grid'
require 'tt_truebend/gl/subdivided_segment'
require 'tt_truebend/geom/polar_projection'
require 'tt_truebend/geom/segment'

module TT::Plugins::TrueBend
  class Bender

    include DrawingHelper
    include ViewConstants

    attr_reader :segment

    def initialize(instance, segment)
      @instance = instance
      @direction = Geom::Vector3d.new(0, 0, 0)
      @angle = 0.0
      @segment = segment
      @segmenter = SubdividedSegmentWidget.new(segment, color: 'green')

      bounds = instance.definition.bounds
      @grid = Grid.new(bounds.width, bounds.height)
      @grid.x_subdivs = @segmenter.subdivisions
      @grid.transformation = instance.transformation
    end

    def reset
      @direction = Geom::Vector3d.new(0, 0, 0)
      @angle = 0.0
    end

    # @param [Geom::Vector3d] direction
    def bend(direction)
      @direction = direction
      @direction.length = segment.length if @direction.length > segment.length
      @angle = Math::PI * (@direction.length / segment.length * 2)
    end

    def commit
    end

    def distance
      radius * (1 - Math.cos(angle / 2))
    end

    def angle
      # radians = length / radius
      @angle
    end

    def angle=(value)
      @angle = value
    end

    def radius
      (@segment.length / angle).to_l
    end

    def chord
      # http://mathworld.wolfram.com/CircularSegment.html
      2 * radius * Math.sin(0.5 * angle)
    end

    def sagitta
      # Compute the arc segment sagitta (distance).
      # https://en.wikipedia.org/wiki/Circular_segment
      # h = R(1 - cos(a/2))
      #     R - sqrt(R^2 - (c^2/4))
      radius * (1 - Math.cos(angle / 2))
    end

    def arc_length
      # s = R * a
      (radius * angle).to_l
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

    def draw(view)
      @segmenter.draw(view)

      reference_points = bend_points(@segmenter.points)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = @segmenter.line_width
      view.drawing_color = 'red'
      view.draw(GL_LINE_STRIP, reference_points)

      view.draw_points(reference_points, 6, DRAW_FILLED_SQUARE, 'red')

      if @direction.valid?
        # p [@segment, @segment.length]
        length = curve_length(reference_points)
        degrees = Sketchup.format_angle(angle)
        view.tooltip = "Radius: #{radius}\nAngle: #{degrees}\nLength: #{@segment.length} (#{length})"

        options = {
          font: 'Arial',
          size: 10,
          bold: true,
          color: 'purple'
        }

        mid = @segmenter.segment.mid_point
        # origin = mid.offset(@direction, radius)

        view.line_stipple = STIPPLE_SOLID
        view.line_width = 1
        view.draw_points([mid, origin], 6, DRAW_CROSS, 'purple')

        view.line_stipple = STIPPLE_SHORT_DASH
        view.drawing_color = 'purple'
        view.draw(GL_LINES, [mid, origin])

        view.drawing_color = 'purple'
        view.line_stipple = STIPPLE_LONG_DASH
        # view.draw(GL_LINE_STRIP, [reference_points.first, origin, reference_points.last])
        view.line_width = 2
        view.draw(GL_LINES, [origin, reference_points.first])
        view.line_width = 1
        view.draw(GL_LINES, [origin, reference_points.last])

        # Radius
        pt = view.screen_coords(Segment.new(mid, origin).mid_point)
        view.draw_text(pt, radius.to_s, options)

        # Angle
        v1 = origin.vector_to(reference_points.first)
        v2 = origin.vector_to(reference_points.last)
        # a = v1.angle_between(v2)
        a = full_angle_between(v1, v2)
        fa = Sketchup.format_angle(a)
        pt = view.screen_coords(origin)
        view.draw_text(pt, "#{fa}° (#{degrees}°)", options)

        # Curve Length
        pt = view.screen_coords(reference_points.first)
        options[:color] = 'red'
        view.draw_text(pt, "#{length} (#{arc_length})", options)

        # Segment Length
        pt = view.screen_coords(@segment.points.last)
        options[:color] = 'green'
        view.draw_text(pt, @segment.length.to_s, options)
      end

      # view.drawing_color = 'maroon'
      # @grid.draw(view)

      if @direction.valid?
        reference_grid = @grid.segments.map(&:points).flatten
        view.line_stipple = STIPPLE_LONG_DASH
        view.line_width = 1
        view.drawing_color = 'green'
        view.draw(GL_LINES, lift(view, reference_grid))

        # TODO: Refactor into a Projection class.
        #       - Convert points to polar coordinates projection.
        #       - Snap points to segmented polar coordinates.

        bounds = BoundingBoxWidget.new(@instance)
        grid = Grid.new(bounds.width, bounds.height)
        grid.x_subdivs = @segmenter.subdivisions

        projection = PolarProjection.new(radius)
        arc_grid = projection.project(grid.segment_points)

        x_axis = origin.vector_to(reference_points.first)
        y_axis = x_axis * Z_AXIS
        y_axis.reverse! if @direction.y < 0
        to_world = Geom::Transformation.axes(origin, x_axis, y_axis)
        arc_grid.each { |pt| pt.transform!(to_world) }

        view.line_stipple = STIPPLE_LONG_DASH
        view.line_width = 1
        view.drawing_color = 'red'
        view.draw(GL_LINES, lift(view, arc_grid))
      end
    end

    private

    # Return the full orientation of the two lines. Going counter-clockwise.
    #
    # @return [Float]
    # @since 2.7.0
    def full_angle_between(vector1, vector2, normal = Z_AXIS)
      direction = (vector1 * vector2) % normal
      angle = vector1.angle_between(vector2)
      angle = 360.degrees - angle if direction < 0.0
      angle
    end

    # Creates a set of +Geom::Point3d+ objects for an arc.
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
    # @since 2.0.0
    def arc(center, xaxis, normal, radius, start_angle, end_angle, num_segments = 12)
      # Generate the first point.
      t = Geom::Transformation.rotation(center, normal, start_angle)
      points = []
      points << center.offset(xaxis, radius).transform(t)
      # Prepare a transformation we can repeat on the last entry in point to complete the arc.
      t = Geom::Transformation.rotation(center, normal, (end_angle - start_angle) / num_segments )
      1.upto(num_segments) { |i|
        points << points.last.transform(t)
      }
      points
    rescue
      p [center, xaxis, normal, radius, start_angle, end_angle, num_segments]
      raise
    end

    def bend_points(points)
      # o = origin
      # r = radius
      # points.map { |point|
      #   # point.offset(X_AXIS, 200.mm)
      #   vector = o.vector_to(point)
      #   o.offset(vector, radius)
      # }

      o = origin
      u = o.vector_to(points.first)
      v = o.vector_to(points.last)
      z = u * v
      if u.valid? && z.valid?
        a2 = angle / 2.0
        a1 = -a2
        x = o.vector_to(Segment.new(points.first, points.last).mid_point)
        arc(o, x, z, radius, a1, a2, @segmenter.subdivisions)
        # arc(o, u, z, radius, 0, angle, @segmenter.subdivisions)
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

  end # class
end # module
