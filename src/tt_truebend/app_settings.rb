require 'tt_truebend/settings'

module TT::Plugins::TrueBend
  class AppSettings < Settings

    def initialize
      super(EXTENSION[:product_id])
    end

    define :error_server, 'sketchup.thomthom.net'

    define :debug, false
    define :debug_draw_boundingbox, false
    define :debug_draw_debug_info, false
    define :debug_draw_local_mesh, false
    define :debug_draw_global_mesh, false
    define :debug_draw_slice_planes, false

  end # class

  SETTINGS = AppSettings.new

end # module TT::Plugins::SUbD
