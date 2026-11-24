require 'tt_truebend/gl/axis_buttons'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/helpers/instance'
require 'tt_truebend/manipulators/drag_handle'
require 'tt_truebend/observers/transaction'
require 'tt_truebend/tools/truebend_menu'
require 'tt_truebend/app_settings'
require 'tt_truebend/bend_axes'
require 'tt_truebend/bender'
require 'tt_truebend/validator'
require 'tt_truebend/vcb_parser'

module TT::Plugins::TrueBend
  class TrueBendTool

    include InstanceHelper
    include TrueBendMenu

    # Raised when the pre-conditions for the tool to operate isn't met.
    class BendError < RuntimeError; end

    # The handle for the direction the instance is currently set up to bend in.
    ACTIVE_HANDLE_COLOR = 'red'.freeze
    # The handles for the other directions the instance can be bent in.
    INACTIVE_HANDLE_COLOR = [96, 96, 96].freeze

    # The arrow keys pick the axis to bend along, the same way they lock the
    # native tools to an axis.
    AXIS_KEYS = {
      VK_RIGHT => BendAxes::X,
      VK_LEFT  => BendAxes::Y,
      VK_UP    => BendAxes::Z,
    }.freeze
    AXIS_KEY_NAMES = ['Right Arrow', 'Left Arrow', 'Up Arrow'].freeze

    # The edges of the bounds that stand for the axis under the cursor.
    HOVER_EDGE_WIDTH = 4

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    def initialize(instance)
      @instance = instance
      @bend_by_distance = false
      @boundingbox = BoundingBoxWidget.new(instance)
      @axis_buttons = AxisButtons.new

      # The ways the instance can be bent, each with the handle to bend it by.
      # @return [Hash{BendAxes => DragHandle}]
      @handles = {}
      # The way the instance is currently set up to bend, and the handle for it.
      @axes = nil
      @manipulator = nil
      @bender = nil
      @cached_direction = nil
      # The axis that a click where the cursor is would choose, and the one the
      # mouse button went down on.
      @hover_axis = nil
      @pressed_axis = nil
      # Bend along the red axis unless the instance has no length along it.
      axes = [BendAxes::X, BendAxes::Y, BendAxes::Z]
      axis = axes.find { |candidate| can_bend_along?(candidate) }
      raise BendError, 'zero length distance to bend' if axis.nil?

      @axis_buttons.disabled = axes.reject { |candidate| can_bend_along?(candidate) }
      select_axis(axis)

      @observer = TransactionObserver.new(&method(:on_transaction))
    end

    def enableVCB?
      true
    end

    def activate
      attach_observers
      update_ui
      Sketchup.active_model.active_view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Sketchup::View] view
    def deactivate(view)
      detach_observers
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Sketchup::View] view
    def suspend(view)
      update_ui
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Sketchup::View] view
    def resume(view)
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onReturn(_view)
      commit_bend
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Sketchup::View] view
    def onCancel(_reason, view)
      view = HighDpiView.new(view)
      reset_bend(view)
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Integer] key
    # @param [Integer] _repeat
    # @param [Integer] _flags
    # @param [Sketchup::View] view
    def onKeyDown(key, _repeat, _flags, view)
      axis = AXIS_KEYS[key]
      return false if axis.nil? || @manipulator.drag?

      choose_axis(axis)
      update_ui
      view.invalidate
      true
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [String] text
    # @param [Sketchup::View] view
    def onUserText(text, view)
      view = HighDpiView.new(view)
      input = VCBParser.new(text)
      if input.modifier?
        if input.segments?
          @bender.subdivisions = input.segments.min(2).value
          return
        else
          # Assuming that if it's not degrees it will be a length unit.
          @bend_by_distance = !input.degrees?
        end
      end
      # Adjust the last value.
      unless @bender.can_bend?
        return UI.beep
      end

      if bend_by_distance?
        # NOTE: This length is relative to the segment length.
        #       Negative values flips the direction.
        #       Values larger than segment length is capped.
        @bender.distance = input.length.value
      else
        @bender.angle = input.degrees.value
      end
      @manipulator.distance = @bender.distance
    rescue VCBParser::InputError, Validator::ValidationError => error
      # TODO: Don't emit error message directly to user.
      UI.messagebox(error.message)
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    ensure
      update_ui
      view.invalidate
    end

    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    def onLButtonDown(flags, x, y, view)
      x, y = DPI.logical_pixels(x, y)
      view = HighDpiView.new(view)
      # The buttons are in front of everything else.
      @pressed_axis = @axis_buttons.pick(x, y)
      unless @pressed_axis || press_handle(flags, x, y, view)
        @pressed_axis = axis_at(x, y, view)
      end
      view.invalidate
      update_ui
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    def onLButtonUp(flags, x, y, view)
      x, y = DPI.logical_pixels(x, y)
      view = HighDpiView.new(view)
      @handles.each_value { |handle| handle.onLButtonUp(flags, x, y, view) }
      # A click is the mouse button going down and up on the same thing.
      pressed_axis = @pressed_axis
      @pressed_axis = nil
      choose_axis(pressed_axis) if pressed_axis && pressed_axis == axis_at(x, y, view)
      update_ui
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Integer] _flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    def onLButtonDoubleClick(_flags, x, y, view)
      x, y = DPI.logical_pixels(x, y)
      view = HighDpiView.new(view)
      # On a button or an edge the second click of a double click is a click
      # like the first, which the mouse button going up completes.
      @pressed_axis = axis_at(x, y, view)
      commit_bend if @pressed_axis.nil?
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    def onMouseMove(flags, x, y, view)
      x, y = DPI.logical_pixels(x, y)
      view = HighDpiView.new(view)
      @handles.each_value { |handle| handle.onMouseMove(flags, x, y, view) }
      @hover_axis = @manipulator.picked? ? nil : axis_at(x, y, view)
      view.tooltip = @hover_axis ? axis_hint(@hover_axis) : ''
      update_ui
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Sketchup::View] view
    def onMouseLeave(view)
      @hover_axis = nil
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @return [Geom::BoundingBox]
    def getExtents
      bounds = Geom::BoundingBox.new
      bounds.add(@bender.bounds)
      @handles.each_value { |handle| bounds.add(handle.bounds) }
      bounds
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    # @param [Sketchup::View] view
    def draw(view)
      view = HighDpiView.new(view)
      @bender.draw(view)
      @boundingbox.draw(view) if SETTINGS.debug_draw_boundingbox?
      @boundingbox.draw_axis(view, @hover_axis, HOVER_EDGE_WIDTH) if @hover_axis
      @handles.each_value { |handle| handle.draw(view) unless handle == @manipulator }
      @manipulator.draw(view)
      draw_axis_buttons(view)
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    private

    # @param [Integer] axis `BendAxes::X`, `BendAxes::Y` or `BendAxes::Z`
    def can_bend_along?(axis)
      BendAxes.along(@instance, axis).all?(&:can_bend?)
    end

    # Offers the mouse button going down to the handles.
    #
    # @param [Integer] flags
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    # @return [DragHandle, nil] The handle that was picked.
    def press_handle(flags, x, y, view)
      # The active handle gets the first go, in case handles overlap on screen.
      handles = [@manipulator] + (@handles.values - [@manipulator])
      picked = handles.find { |handle|
        handle.onLButtonDown(flags, x, y, view)
        handle.picked?
      }
      select_bend(@handles.key(picked)) if picked && picked != @manipulator
      picked
    end

    # Bends along the given axis. Choosing the axis already in use switches to
    # the other direction the instance can be bent in along that axis.
    #
    # @param [Integer] axis `BendAxes::X`, `BendAxes::Y` or `BendAxes::Z`
    def choose_axis(axis)
      if axis == @axes.axis
        select_bend((@handles.keys - [@axes]).first)
      elsif can_bend_along?(axis)
        select_axis(axis)
      else
        UI.beep
      end
    end

    # The axis that a click at the given position in the viewport chooses.
    # There is a button for each axis, and the edges of the bounds of the
    # instance stand for the axis they run along.
    #
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    # @return [Integer, nil] `BendAxes::X`, `BendAxes::Y` or `BendAxes::Z`
    def axis_at(x, y, view)
      axis = @axis_buttons.pick(x, y)
      return axis if axis
      # The handles go before the edges they are in front of.
      return nil if @handles.each_value.any? { |handle| handle.at?(x, y, view) }

      @boundingbox.pick_axis(x, y, view)
    end

    # What choosing the given axis does.
    #
    # @param [Integer] axis `BendAxes::X`, `BendAxes::Y` or `BendAxes::Z`
    # @return [String]
    def axis_hint(axis)
      name = AXIS_NAMES[axis].downcase
      if axis == @axes.axis
        "Switch the bend direction (#{AXIS_KEY_NAMES[axis]})"
      elsif can_bend_along?(axis)
        "Bend along the #{name} (#{AXIS_KEY_NAMES[axis]})"
      else
        "No length to bend along the #{name}"
      end
    end

    # @param [Sketchup::View] view
    def draw_axis_buttons(view)
      @axis_buttons.selected = @axes.axis
      @axis_buttons.hovered = @hover_axis
      if @hover_axis
        @axis_buttons.text = axis_hint(@hover_axis)
      else
        @axis_buttons.text = "Bending along the #{AXIS_NAMES[@axes.axis].downcase}"
      end
      @axis_buttons.draw(view)
    end

    # Sets which axis of the instance to bend it along. The bend is kept.
    #
    # @param [Integer] axis `BendAxes::X`, `BendAxes::Y` or `BendAxes::Z`
    def select_axis(axis)
      options = BendAxes.along(@instance, axis)
      @handles = options.each_with_object({}) { |axes, handles|
        handles[axes] = create_handle(axes)
      }
      select_bend(options.first)
    end

    # Sets which of the directions on offer to bend the instance in. The bend is
    # kept by the value the Measurements box is showing: its angle, or its
    # distance when a distance was typed.
    #
    # @param [BendAxes] axes One of the keys in `@handles`.
    def select_bend(axes)
      previous = @bender
      @bender = Bender.new(@instance, axes.segment, axes.normal)
      @bender.segmented = SETTINGS.bend_segmented?
      @bender.soft_smooth = SETTINGS.bend_soft_smooth?
      @cached_direction = nil

      @axes = axes
      @manipulator = @handles[axes]
      @handles.each_value { |handle| handle.color = INACTIVE_HANDLE_COLOR }
      @manipulator.color = ACTIVE_HANDLE_COLOR
      return if previous.nil?

      @bender.subdivisions = previous.subdivisions
      if bend_by_distance?
        @bender.bend_as_far_as(previous)
      else
        @bender.bend_like(previous)
      end
    end

    # @param [BendAxes] axes
    # @return [DragHandle]
    def create_handle(axes)
      handle = DragHandle.new(axes.face_center, axes.normal)
      handle.on_drag { |direction|
        @cached_direction ||= @bender.direction
        @bender.bend(@cached_direction + direction)
      }
      handle.on_drag_complete {
        @cached_direction = nil
      }
      handle
    end

    def commit_bend
      return unless @bender.can_bend?

      model = Sketchup.active_model
      model.start_operation('Bend', true)
      @bender.commit
      model.commit_operation
      model.tools.pop_tool
    end

    # @param [Sketchup::View] view
    def reset_bend(view)
      @bender.reset
      @handles.each_value(&:reset)
      update_ui
      view.invalidate
    end

    def bend_by_distance?
      @bend_by_distance
    end

    def update_ui
      if @manipulator.drag?
        Sketchup.status_text = 'Drag to adjust the amount of bend.'
      else
        Sketchup.status_text = 'Pick a handle to start bending the instance. ' \
                               'Click an axis button or an edge of the bounding box, ' \
                               'or use the arrow keys, to bend along another axis.'
      end
      if bend_by_distance?
        Sketchup.vcb_label = 'Distance'
        Sketchup.vcb_value = @bender.distance
      else
        Sketchup.vcb_label = 'Angle'
        Sketchup.vcb_value = Sketchup.format_angle(@bender.angle)
      end
    end

    # @param [Sketchup::Model] model
    def on_transaction(model, _type)
      model.select_tool(nil)
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def attach_observers
      model = Sketchup.active_model
      return if model.nil?

      model.remove_observer(@observer)
      model.add_observer(@observer)
    end

    def detach_observers
      model = Sketchup.active_model
      return if model.nil?

      model.remove_observer(@observer)
    end

  end # class
end # module
