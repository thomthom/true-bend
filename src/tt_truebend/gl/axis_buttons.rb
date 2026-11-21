require 'tt_truebend/constants/view'
require 'tt_truebend/gl/drawing_helper'

module TT::Plugins::TrueBend
  # A row of buttons in the corner of the viewport, one for each axis, with a
  # line of text next to them. Positions are in logical pixels.
  class AxisButtons

    include DrawingHelper
    include ViewConstants

    # Where the row is in the viewport.
    LEFT = 16
    TOP = 16
    # The buttons are square.
    SIZE = 24
    SPACING = 6
    # How far in from the edge of a button its colour starts, unless the
    # button is the selected one, which is filled.
    SWATCH_INSET = 6

    TEXT_SPACING = 10
    TEXT_HEIGHT = 16
    TEXT_OPTIONS = {
      font: 'Arial',
      size: 10,
      bold: true,
      color: [48, 48, 48],
    }.freeze

    BACKGROUND_COLOR = [255, 255, 255].freeze
    BORDER_COLOR = [128, 128, 128].freeze
    ACTIVE_BORDER_COLOR = [32, 32, 32].freeze
    DISABLED_BACKGROUND_COLOR = [224, 224, 224].freeze
    DISABLED_COLOR = [176, 176, 176].freeze

    # @return [Integer, nil] The axis of the button that shows as chosen.
    attr_accessor :selected

    # @return [Integer, nil] The axis of the button that shows as being under
    #   the cursor.
    attr_accessor :hovered

    # @return [Array<Integer>] The axes of the buttons that show as
    #   unavailable.
    attr_accessor :disabled

    # @return [String] The text next to the buttons.
    attr_accessor :text

    def initialize
      @selected = nil
      @hovered = nil
      @disabled = []
      @text = ''
    end

    # @param [Integer] x
    # @param [Integer] y
    # @return [Integer, nil] The axis of the button at the given position.
    def pick(x, y)
      (0..2).find { |axis|
        left, top, right, bottom = rectangle(axis)
        x.between?(left, right) && y.between?(top, bottom)
      }
    end

    # The middle of the button for the given axis.
    #
    # @param [Integer] axis
    # @return [Array(Integer, Integer)]
    def center(axis)
      left, top, right, bottom = rectangle(axis)
      [(left + right) / 2, (top + bottom) / 2]
    end

    # @param [Sketchup::View] view
    def draw(view)
      3.times { |axis| draw_button(view, axis) }
      draw_text(view)
    end

    private

    # @param [Integer] axis
    # @return [Array(Integer, Integer, Integer, Integer)] Left, top, right and
    #   bottom.
    def rectangle(axis)
      left = LEFT + (axis * (SIZE + SPACING))
      [left, TOP, left + SIZE, TOP + SIZE]
    end

    # @param [Integer] left
    # @param [Integer] top
    # @param [Integer] right
    # @param [Integer] bottom
    # @param [Integer] inset
    # @return [Array<Geom::Point3d>]
    def quad(left, top, right, bottom, inset = 0)
      [
        Geom::Point3d.new(left + inset,  top + inset,    0),
        Geom::Point3d.new(right - inset, top + inset,    0),
        Geom::Point3d.new(right - inset, bottom - inset, 0),
        Geom::Point3d.new(left + inset,  bottom - inset, 0),
      ]
    end

    # @param [Sketchup::View] view
    # @param [Integer] axis
    def draw_button(view, axis)
      disabled = @disabled.include?(axis)
      selected = axis == @selected
      active = !disabled && (selected || axis == @hovered)
      bounds = rectangle(axis)

      view.drawing_color = disabled ? DISABLED_BACKGROUND_COLOR : BACKGROUND_COLOR
      view.draw2d(GL_QUADS, quad(*bounds))

      if disabled
        view.drawing_color = DISABLED_COLOR
      else
        set_axis_color(view, axis)
      end
      view.draw2d(GL_QUADS, quad(*bounds, selected ? 0 : SWATCH_INSET))

      view.line_stipple = STIPPLE_SOLID
      view.line_width = active ? 2 : 1
      view.drawing_color = active ? ACTIVE_BORDER_COLOR : BORDER_COLOR
      view.draw2d(GL_LINE_LOOP, quad(*bounds))
    end

    # @param [Sketchup::View] view
    def draw_text(view)
      return if @text.empty?

      left = rectangle(2)[2] + TEXT_SPACING
      top = TOP + ((SIZE - TEXT_HEIGHT) / 2)
      view.draw_text(Geom::Point3d.new(left, top, 0), @text, TEXT_OPTIONS)
    end

  end # class
end # module
