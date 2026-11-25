require 'tt_truebend/tools/truebend_options'
require 'tt_truebend/app_settings'
require 'tt_truebend/bend_axes'

module TT::Plugins::TrueBend
  # The context menu of `TrueBendTool`. The option items rely on the tool also
  # including `TrueBendOptions`.
  module TrueBendMenu

    # Menu titles for the axes an instance can be bent along, by axis index.
    AXIS_NAMES = ['Red Axis', 'Green Axis', 'Blue Axis'].freeze

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
        reset_bend(@model.active_view)
      }
      menu.set_validation_proc(id) {
        @bender.can_bend? ? MF_ENABLED : MF_DISABLED | MF_GRAYED
      }

      menu.add_separator
      add_axis_menus(menu)
      menu.add_separator

      id = menu.add_item('Segmented') {
        toggle_segmented
      }
      menu.set_validation_proc(id) {
        @bender.segmented ? MF_CHECKED : MF_ENABLED
      }

      id = menu.add_item('Soften/Smooth Segments') {
        toggle_soft_smooth
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
    def add_axis_menus(menu)
      submenu = menu.add_submenu('Bend Along')
      AXIS_NAMES.each_with_index { |name, axis|
        id = submenu.add_item(name) {
          select_axis(axis) unless axis == @axes.axis
          update_ui
          @model.active_view.invalidate
        }
        submenu.set_validation_proc(id) {
          if axis == @axes.axis
            MF_CHECKED
          elsif can_bend_along?(axis)
            MF_ENABLED
          else
            MF_DISABLED | MF_GRAYED
          end
        }
      }
    end

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
        @model.active_view.invalidate
      }
      menu.set_validation_proc(id) {
        SETTINGS.send(getter) ? MF_CHECKED : MF_ENABLED
      }
    end

  end # module
end # module
