require 'tt_truebend/app_settings'

module TT::Plugins::TrueBend
  # The context menu of `TrueBendTool`.
  module TrueBendMenu

    # rubocop:disable Metrics/MethodLength
    # @param [Sketchup::Menu] menu
    def getMenu(menu)
      id = menu.add_item('Commit') {
        commit_bend
      }
      menu.set_validation_proc(id) {
        @bender.can_bend? ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      }

      id = menu.add_item('Cancel') {
        reset_bend(Sketchup.active_model.active_view)
      }
      menu.set_validation_proc(id) {
        @bender.can_bend? ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      }

      menu.add_separator

      id = menu.add_item('Segmented') {
        @bender.segmented = !@bender.segmented
        SETTINGS.bend_segmented = @bender.segmented
      }
      menu.set_validation_proc(id) {
        @bender.segmented ? MF_CHECKED : MF_ENABLED
      }

      id = menu.add_item('Soften/Smooth Segments') {
        @bender.soft_smooth = !@bender.soft_smooth
        SETTINGS.bend_soft_smooth = @bender.soft_smooth
      }
      menu.set_validation_proc(id) {
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

    private

    # @param [Sketchup::Menu] menu
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
      menu.set_validation_proc(id) {
        SETTINGS.send(getter) ? MF_CHECKED : MF_ENABLED
      }
    end

  end # module
end # module
