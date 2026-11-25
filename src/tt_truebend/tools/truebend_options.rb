require 'tt_truebend/gl/option_buttons'
require 'tt_truebend/app_settings'

module TT::Plugins::TrueBend
  # Handles the options of `TrueBendTool`. The context menu and the viewport
  # buttons both use it.
  module TrueBendOptions

    # These are the tooltips for the option buttons.
    OPTION_HINTS = {
      angle:       'Type the angle of the bend (45deg)',
      distance:    'Type the distance of the bend (500mm)',
      radius:      'Type the radius of the bend (500mmr)',
      sagitta:     'Type the sagitta of the bend (50mmsg)',
      segmented:   'Bend in straight segments',
      soft_smooth: 'Soften and smooth the edges between the segments',
    }.freeze

    # This is the tooltip for the soften/smooth button while it is disabled.
    SOFT_SMOOTH_UNAVAILABLE = 'The edges of a bend that is not segmented are ' \
                              'always soft and smooth'.freeze

    private

    def toggle_segmented
      @bender.segmented = !@bender.segmented
      SETTINGS.bend_segmented = @bender.segmented
    end

    def toggle_soft_smooth
      @bender.soft_smooth = !@bender.soft_smooth
      SETTINGS.bend_soft_smooth = @bender.soft_smooth
    end

    # @param [Symbol] option One of `OptionButtons::OPTIONS`.
    def choose_option(option)
      case option
      when :segmented
        toggle_segmented
      when :soft_smooth
        return UI.beep unless @bender.segmented

        toggle_soft_smooth
      else
        self.input_mode = option
      end
    end

    # @param [Symbol] option One of `OptionButtons::OPTIONS`.
    # @return [String] The tooltip for the option's button.
    def option_hint(option)
      return SOFT_SMOOTH_UNAVAILABLE if option == :soft_smooth && !@bender.segmented

      OPTION_HINTS[option]
    end

    # @return [Array<Symbol>] The enabled options.
    def selected_options
      options = [@input_mode]
      options << :segmented if @bender.segmented
      options << :soft_smooth if @bender.soft_smooth
      options
    end

    # @param [Sketchup::View] view
    def draw_option_buttons(view)
      @option_buttons.selected = selected_options
      @option_buttons.disabled = @bender.segmented ? [] : [:soft_smooth]
      @option_buttons.hovered = @hover_option
      @option_buttons.draw(view)
    end

  end # module
end # module
