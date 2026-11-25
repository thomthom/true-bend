require 'tt_truebend/constants/view'
require 'tt_truebend/gl/axis_buttons'

module TT::Plugins::TrueBend
  # Viewport buttons for the tool options. Positions are in logical pixels.
  class OptionButtons

    include ViewConstants

    SIZE = AxisButtons::SIZE
    SPACING = AxisButtons::SPACING
    GROUP_SPACING = 16
    LEFT = AxisButtons::LEFT + (3 * (SIZE + SPACING)) - SPACING + GROUP_SPACING
    TOP = AxisButtons::TOP

    # VCB input modes, then bend options.
    GROUPS = [
      [:angle, :distance, :radius],
      [:segmented, :soft_smooth],
    ].freeze
    OPTIONS = GROUPS.flatten.freeze

    SELECTED_BACKGROUND_COLOR = [196, 218, 246].freeze
    GLYPH_COLOR = [48, 48, 48].freeze
    GLYPH_WIDTH = 2

    # Angles are in degrees, counter-clockwise from the X axis. Y points down,
    # as in screen coordinates.
    #
    # @param [Array(Numeric, Numeric)] center
    # @param [Numeric] radius
    # @param [Numeric] start_angle
    # @param [Numeric] end_angle
    # @param [Integer] segments
    # @return [Array<Array(Float, Float)>]
    def self.arc(center, radius, start_angle, end_angle, segments)
      x, y = center
      (0..segments).map { |i|
        degrees = start_angle + ((end_angle - start_angle) * i / segments.to_f)
        angle = degrees * Math::PI / 180.0
        [x + (radius * Math.cos(angle)), y - (radius * Math.sin(angle))]
      }
    end

    # Button icons as polylines: `[stipple, points]`. Points are relative to
    # the top left corner of the button.
    GLYPHS = {
      angle:       [
        [STIPPLE_SOLID, [[19, 19], [5, 19], [14, 5]]],
        [STIPPLE_SOLID, arc([5, 19], 9, 0, 57, 4)],
      ],
      distance:    [
        [STIPPLE_SOLID, [[5, 12], [19, 12]]],
        [STIPPLE_SOLID, [[5, 7], [5, 17]]],
        [STIPPLE_SOLID, [[19, 7], [19, 17]]],
      ],
      radius:      [
        [STIPPLE_SOLID, arc([12, 12], 8, 0, 360, 16)],
        [STIPPLE_SOLID, [[12, 12], arc([12, 12], 8, 35, 35, 1).first]],
      ],
      segmented:   [
        [STIPPLE_SOLID, [[3, 18], [8, 9], [16, 9], [21, 18]]],
      ],
      # A face with a soft (dashed) edge across it.
      soft_smooth: [
        [STIPPLE_SOLID, [[4, 6], [20, 6], [20, 18], [4, 18], [4, 6]]],
        [STIPPLE_SHORT_DASH, [[12, 6], [12, 18]]],
      ],
    }.freeze

    # @return [Array<Symbol>] Options drawn as selected.
    attr_accessor :selected

    # @return [Symbol, nil] Option drawn as hovered.
    attr_accessor :hovered

    # @return [Array<Symbol>] Options drawn as disabled.
    attr_accessor :disabled

    def initialize
      @selected = []
      @hovered = nil
      @disabled = []
    end

    # @param [Integer] x
    # @param [Integer] y
    # @return [Symbol, nil]
    def pick(x, y)
      OPTIONS.find { |option|
        left, top, right, bottom = rectangle(option)
        x.between?(left, right) && y.between?(top, bottom)
      }
    end

    # @param [Symbol] option
    # @return [Array(Integer, Integer)]
    def center(option)
      left, top, right, bottom = rectangle(option)
      [(left + right) / 2, (top + bottom) / 2]
    end

    # @param [Sketchup::View] view
    def draw(view)
      OPTIONS.each { |option| draw_button(view, option) }
    end

    private

    # @param [Symbol] option
    # @return [Array(Integer, Integer, Integer, Integer)] Left, top, right and
    #   bottom.
    def rectangle(option)
      group = GROUPS.index { |options| options.include?(option) }
      index = OPTIONS.index(option)
      left = LEFT + (index * (SIZE + SPACING)) + (group * (GROUP_SPACING - SPACING))
      [left, TOP, left + SIZE, TOP + SIZE]
    end

    # @param [Integer] left
    # @param [Integer] top
    # @param [Integer] right
    # @param [Integer] bottom
    # @return [Array<Geom::Point3d>]
    def quad(left, top, right, bottom)
      [
        Geom::Point3d.new(left,  top,    0),
        Geom::Point3d.new(right, top,    0),
        Geom::Point3d.new(right, bottom, 0),
        Geom::Point3d.new(left,  bottom, 0),
      ]
    end

    # @param [Sketchup::View] view
    # @param [Symbol] option
    def draw_button(view, option)
      disabled = @disabled.include?(option)
      selected = @selected.include?(option)
      active = !disabled && (selected || option == @hovered)
      bounds = rectangle(option)

      view.drawing_color = background_color(disabled, selected)
      view.draw2d(GL_QUADS, quad(*bounds))

      view.drawing_color = disabled ? AxisButtons::DISABLED_COLOR : GLYPH_COLOR
      draw_glyph(view, option, bounds[0], bounds[1])

      view.line_stipple = STIPPLE_SOLID
      view.line_width = active ? 2 : 1
      view.drawing_color = active ? AxisButtons::ACTIVE_BORDER_COLOR : AxisButtons::BORDER_COLOR
      view.draw2d(GL_LINE_LOOP, quad(*bounds))
    end

    # @param [Boolean] disabled
    # @param [Boolean] selected
    # @return [Array(Integer, Integer, Integer)]
    def background_color(disabled, selected)
      return AxisButtons::DISABLED_BACKGROUND_COLOR if disabled

      selected ? SELECTED_BACKGROUND_COLOR : AxisButtons::BACKGROUND_COLOR
    end

    # @param [Sketchup::View] view
    # @param [Symbol] option
    # @param [Integer] left
    # @param [Integer] top
    def draw_glyph(view, option, left, top)
      view.line_width = GLYPH_WIDTH
      GLYPHS[option].each { |stipple, points|
        view.line_stipple = stipple
        line = points.map { |x, y| Geom::Point3d.new(left + x, top + y, 0) }
        view.draw2d(GL_LINE_STRIP, line)
      }
    end

  end # class
end # module
