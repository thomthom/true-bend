require 'tt_truebend/constants/view'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/helpers/boundingbox'

module TT::Plugins::TrueBend
  class DragHandle

    include ViewConstants

    attr_accessor :origin, :normal, :color, :size
    attr_accessor :debug
    attr_reader :direction

    # @param [Geom::Point3d] origin
    # @param [Geom::Vector3d] normal
    # @param [Sketchup::Color] color
    # @param [Numeric] size
    def initialize(origin, normal, color: [255, 128, 0], size: 50)
      @origin = origin
      @normal = normal
      @color = color
      @size = size

      @direction = Geom::Vector3d.new(0, 0, 0)

      @start_pick = nil
      @drag = false
      @mouse_down_position = nil
      @mouse_position = ORIGIN.clone

      @events = {}

      @debug = false
    end

    def reset
      @drag = false
      @mouse_down_position = nil
    end

    def can_adjust?
      # !@direction.nil?
      false
    end

    def drag?
      @drag
    end

    def distance
      @direction.length
    end

    def bounds
      view = Sketchup.active_model.active_view
      points = handle_points(view)
      bounds = Geom::BoundingBox.new
      bounds.add(points)
      bounds
    end

    def draw(view)
      points = handle_points(view)
      if @mouse_down_position && @direction && @direction.valid?
        points.last.offset!(@direction)
      end

      view.line_stipple = STIPPLE_SOLID
      view.line_width = mouse_over?(view) ? 3 : 2
      view.drawing_color = @color
      view.draw(GL_LINES, points)

      view.draw_points(points, 6, DRAW_FILLED_SQUARE, @color)

      return unless debug

      if @mouse_down_position && @direction
        target = @origin.clone
        target.offset!(@direction) if @direction.valid?
        view.line_stipple = STIPPLE_SOLID
        view.draw_points([target], 10, DRAW_FILLED_TRIANGLE, @color)
      end

      if @mouse_down_position
        debug_points = [@mouse_down_position, @mouse_position]

        view.line_width = 1
        view.draw_points(debug_points, 6, DRAW_CROSS, 'purple')

        view.line_stipple = STIPPLE_SHORT_DASH
        view.drawing_color = 'purple'
        view.draw2d(GL_LINES, debug_points)

        if @start_pick
          view.line_stipple = STIPPLE_SOLID
          view.draw_points([@start_pick], 10, DRAW_PLUS, 'purple')
        end
      end

      x, y = *@mouse_position.to_a
      handle = handle_points(view)
      pick_ray = view.pickray(x, y)
      points = Geom.closest_points(handle, pick_ray)
      view.line_width = 1
      view.draw_points(points, 6, DRAW_CROSS, 'green')
      view.line_stipple = STIPPLE_SHORT_DASH
      view.drawing_color = 'green'
      view.draw(GL_LINES, points)
    end


    def on_drag(&block)
      @events[:drag] = block
    end

    def on_drag_complete(&block)
      @events[:drag_complete] = block
    end


    def onLButtonDown(flags, x, y, view)
      # puts 'onLButtonDown'
      # p mouse_over?(view)
      @mouse_position = Geom::Point3d.new(x, y, 0)
      @direction = Geom::Vector3d.new(0, 0, 0)
      # @mouse_down_position = @mouse_position.clone if mouse_over?(view)

      picked = pick_point(x, y, view)
      if picked
        @start_pick = picked
        @mouse_down_position = @mouse_position.clone
      end
    end

    def onLButtonUp(flags, x, y, view)
      # puts 'onLButtonUp'
      # picked = pick_point(x, y, view)
      if @start_pick
        picked = pick_closest(x, y, view)
        @direction = @start_pick.vector_to(picked)
        @events[:drag_complete].call if @events[:drag_complete]
      end

      @mouse_down_position = nil
      @drag = false
    end

    def onMouseMove(flags, x, y, view)
      # puts 'onMouseMove'
      @mouse_position = Geom::Point3d.new(x, y, 0)
      # p @mouse_position
      if @mouse_down_position
        @drag = @mouse_position != @mouse_down_position

        # picked = pick_point(x, y, view)
        picked = pick_closest(x, y, view)
        @direction = @start_pick.vector_to(picked)
        @events[:drag].call if @events[:drag]
      else
        @drag = false
      end
    end

    private

    # @return [Integer] Segment index.
    def pick_segment(x, y, view)
      handle = handle_points(view)
      ph = view.pick_helper
      ph.pick_segment(handle, x, y, 10)
    end

    def pick_point(x, y, view)
      index = pick_segment(x, y, view)
      return nil unless index
      pick_closest(x, y, view)
    end

    def pick_closest(x, y, view)
      handle = handle_points(view)
      pick_ray = view.pickray(x, y)
      points = Geom.closest_points(handle, pick_ray)
      points.first
    end

    def handle_points(view)
      distance = view.pixels_to_model(@size, @origin)
      handle_point = @origin.offset(@normal, distance)
      [@origin, handle_point]
    end

    def mouse_over?(view)
      x, y = *@mouse_position.to_a
      !!pick_segment(x, y, view)
    end

  end # class
end # module
