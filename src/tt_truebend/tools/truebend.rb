require 'tt_truebend/constants/boundingbox'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/manipulators/drag_handle'
require 'tt_truebend/app_settings'
require 'tt_truebend/bender'
require 'tt_truebend/vcb_parser'

module TT::Plugins::TrueBend
  class TrueBendTool

    include BoundingBoxConstants

    def initialize(instance)
      @bend_by_distance = false
      @boundingbox = BoundingBoxWidget.new(instance)

      segment = @boundingbox.segments.first
      polygon = @boundingbox.polygon(BB_POLYGON_FRONT)

      @bender = Bender.new(instance, segment, polygon.normal)
      @bender.segmented = SETTINGS.bend_segmented?
      @bender.soft_smooth = SETTINGS.bend_soft_smooth?

      @manipulator = DragHandle.new(polygon.center, polygon.normal, color: 'red')

      @cached_direction = nil
      @manipulator.on_drag { |direction|
        @cached_direction ||= @bender.direction
        @bender.bend(@cached_direction + direction)
      }
      @manipulator.on_drag_complete {
        @cached_direction = nil
      }
    end

    # rubocop:disable Metrics/MethodLength
    def getMenu(menu)
      id = menu.add_item('Commit') {
        commit_bend
      }
      menu.set_validation_proc(id)  {
        @bender.can_bend? ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      }

      id = menu.add_item('Cancel') {
        reset_bend(Sketchup.active_model.active_view)
      }
      menu.set_validation_proc(id)  {
        @bender.can_bend? ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      }

      menu.add_separator

      id = menu.add_item('Segmented') {
        @bender.segmented = !@bender.segmented
        SETTINGS.bend_segmented = @bender.segmented
      }
      menu.set_validation_proc(id)  {
        @bender.segmented ? MF_CHECKED : MF_ENABLED
      }

      id = menu.add_item('Soften/Smooth Segments') {
        @bender.soft_smooth = !@bender.soft_smooth
        SETTINGS.bend_soft_smooth = @bender.soft_smooth
      }
      menu.set_validation_proc(id)  {
        if @bender.segmented
          @bender.soft_smooth ? MF_CHECKED : MF_ENABLED
        else
          MF_DISABLED | MF_GRAYED | MF_CHECKED
        end
      }

      add_debug_menus(menu)
      true # `nil` or `false` will cause native menu to display.
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end
    # rubocop:enable Metrics/MethodLength

    def enableVCB?
      true
    end

    def activate
      update_ui
      Sketchup.active_model.active_view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def deactivate(view)
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def suspend(view)
      update_ui
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

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

    def onCancel(_reason, view)
      reset_bend(view)
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onUserText(text, view)
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
      begin
        if bend_by_distance?
          @bender.distance = input.length.value
        else
          @bender.angle = input.degrees.value
        end
      rescue ArgumentError => error
        # TODO: Don't emit error message directly to user.
        UI.messagebox(error.message)
        return
      end
      @manipulator.distance = @bender.distance
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    ensure
      update_ui
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @manipulator.onLButtonDown(flags, x, y, view)
      view.invalidate
      update_ui
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onLButtonUp(flags, x, y, view)
      @manipulator.onLButtonUp(flags, x, y, view)
      update_ui
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onLButtonDoubleClick(_flags, _x, _y, _view)
      commit_bend
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def onMouseMove(flags, x, y, view)
      @manipulator.onMouseMove(flags, x, y, view)
      update_ui
      view.invalidate
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      bounds.add(@bender.bounds)
      bounds.add(@manipulator.bounds)
      bounds
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    def draw(view)
      @bender.draw(view)
      @boundingbox.draw(view) if SETTINGS.debug_draw_boundingbox?
      @manipulator.draw(view)
    rescue Exception => exception
      ERROR_REPORTER.handle(exception)
    end

    private

    # @param [Sketchup::Menu]
    def add_debug_menus(menu)
      return unless SETTINGS.debug?
      menu.add_separator
      add_setting_toggle(menu, :debug_draw_boundingbox)
      add_setting_toggle(menu, :debug_draw_debug_info)
      add_setting_toggle(menu, :debug_draw_local_mesh)
      add_setting_toggle(menu, :debug_draw_global_mesh)
      add_setting_toggle(menu, :debug_draw_slice_planes)
    end

    # @param [Sketchup::Menu] menu
    # @param [Symbol] setting
    def add_setting_toggle(menu, setting)
      setter = "#{setting}=".to_sym
      getter = "#{setting}?".to_sym
      title = setting.to_s.split('_').map(&:capitalize).join(' ')
      id = menu.add_item(title) {
        SETTINGS.send(setter, !SETTINGS.send(getter))
        Sketchup.active_model.active_view.invalidate
      }
      menu.set_validation_proc(id)  {
        SETTINGS.send(getter) ? MF_CHECKED : MF_ENABLED
      }
    end

    def commit_bend
      return unless @bender.can_bend?
      model = Sketchup.active_model
      model.start_operation('Bend', true)
      @bender.commit
      model.commit_operation
      model.tools.pop_tool
    end

    def reset_bend(view)
      @bender.reset
      @manipulator.reset
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
        Sketchup.status_text = 'Pick a handle to start bending the instance.'
      end
      if bend_by_distance?
        Sketchup.vcb_label = 'Distance'
        Sketchup.vcb_value = @bender.distance
      else
        Sketchup.vcb_label = 'Angle'
        Sketchup.vcb_value = Sketchup.format_angle(@bender.angle)
      end
    end

  end # class
end # module
