require 'tt_truebend/settings'

module TT::Plugins::TrueBend
  class AppSettings < Settings

    def initialize
      super(EXTENSION[:product_id])
    end

    define :error_server, 'sketchup.thomthom.net'

    define :bend_segmented, true
    define :bend_soft_smooth, true

    define :dpi_scale_factor, 1.0

    define :debug, false

    define :debug_draw_boundingbox, false
    define :debug_draw_debug_info, false
    define :debug_draw_local_mesh, false
    define :debug_draw_global_mesh, false
    define :debug_draw_slice_planes, false

    define :debug_force_high_dpi, false
    define :debug_high_dpi_scaling_factor, 2.0

  end # class

  SETTINGS = AppSettings.new

end # module
