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

    def initialize(instance, segment, normal)
      @instance = instance
      @normal = normal
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

    def concave?
      @direction.samedirection?(@normal)
    end

    def convex?
      !concave?
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
        bounds = BoundingBoxWidget.new(@instance)
        grid = Grid.new(bounds.width, bounds.height)
        grid.x_subdivs = @segmenter.subdivisions

        x_axis = origin.vector_to(polar_points.first)
        projection = PolarProjection.new(radius)
        projection.axes(origin, x_axis, convex?)
        arc_grid = projection.project(grid.segment_points)

        view.line_stipple = STIPPLE_LONG_DASH
        view.line_width = 1
        view.drawing_color = 'red'
        view.draw(GL_LINES, lift(view, arc_grid))
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

  end # class
end # module
