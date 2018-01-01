require 'tt_truebend/constants/view'

module TT::Plugins::TrueBend
  class Grid

    include ViewConstants

    attr_accessor :x_subdivs, :y_subdivs
    attr_accessor :transformation

    def initialize(width, height)
      @width = width
      @height = height

      @x_subdivs = 3
      @y_subdivs = 3

      @transformation = IDENTITY
    end

    def draw(view)
      solid = []
      stippled = []

      [x_grid_segments, y_grid_segments].each { |segments|
        solid.concat(segments.pop.points)
        solid.concat(segments.shift.points)
        stippled.concat(segments.map(&:points).flatten)
      }

      view.line_stipple = STIPPLE_SOLID
      view.line_width = 2
      view.draw(GL_LINES, solid)

      view.line_stipple = STIPPLE_SHORT_DASH
      view.line_width = 1
      view.draw(GL_LINES, stippled)
    end

    def segments
      # solid = []
      # stippled = []
      # [x_segments, y_segments].each { |n_segments|
      #   solid << n_segments.pop
      #   solid << n_segments.shift
      #   stippled.concat(n_segments)
      # }
      # [solid, stippled]
      [x_segments, y_segments].flatten
    end

    # private

    def x_grid_segments
      y_step = @height / y_subdivs
      (0..y_subdivs).map { |i|
        y = y_step * i
        pt1 = Geom::Point3d.new(0, y, 0)
        pt2 = Geom::Point3d.new(@width, y, 0)
        Segment.new(pt1, pt2).transform!(@transformation)
      }
    end

    def y_grid_segments
      x_step = @width / x_subdivs
      (0..x_subdivs).map { |i|
        x = x_step * i
        pt1 = Geom::Point3d.new(x, 0, 0)
        pt2 = Geom::Point3d.new(x, @height, 0)
        Segment.new(pt1, pt2).transform!(@transformation)
      }
    end

    def x_segments
      result = []
      x_step = @width / x_subdivs
      y_step = @height / y_subdivs
      (0...x_subdivs).each { |x|
        x1 = x_step * x
        x2 = x_step * (x + 1)
        (0..y_subdivs).each { |i|
          y = y_step * i
          pt1 = Geom::Point3d.new(x1, y, 0)
          pt2 = Geom::Point3d.new(x2, y, 0)
          result << Segment.new(pt1, pt2).transform!(@transformation)
        }
      }
      result
    end

    def y_segments
      result = []
      x_step = @width / x_subdivs
      y_step = @height / y_subdivs
      (0...y_subdivs).each { |y|
        y1 = y_step * y
        y2 = y_step * (y + 1)
        (0..x_subdivs).each { |i|
          x = x_step * i
          pt1 = Geom::Point3d.new(x, y1, 0)
          pt2 = Geom::Point3d.new(x, y2, 0)
          result << Segment.new(pt1, pt2).transform!(@transformation)
        }
      }
      result
    end

  end # class
end # module
