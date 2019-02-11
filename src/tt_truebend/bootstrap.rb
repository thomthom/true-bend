require 'tt_truebend/app_settings'

module TT::Plugins::TrueBend

  ### CONSTANTS ### ------------------------------------------------------------

  PLATFORM_WIN = (Sketchup.platform == :platform_win)
  PLATFORM_OSX = (Sketchup.platform == :platform_osx)

  # Minimum version of SketchUp required to run the extension.
  MINIMUM_SKETCHUP_VERSION = 14


  ### COMPATIBILITY CHECK ### --------------------------------------------------

  # TODO: Migrate this version check handling into a reusable Skippy module.
  if Sketchup.version.to_i < MINIMUM_SKETCHUP_VERSION

    # Not localized because we don't want the Translator and related
    # dependencies to be forced to be compatible with older SketchUp versions.
    version_name = "20#{MINIMUM_SKETCHUP_VERSION}"
    message = "#{EXTENSION[:name]} require SketchUp #{version_name} or newer."
    messagebox_open = false # Needed to avoid opening multiple message boxes.
    # Defer with a timer in order to let SketchUp fully load before displaying
    # modal dialog boxes.
    UI.start_timer(0, false) {
      unless messagebox_open
        messagebox_open = true
        UI.messagebox(message)
        # Must defer the disabling of the extension as well otherwise the
        # setting won't be saved. I assume SketchUp save this setting after it
        # loads the extension.
        @extension.uncheck
      end
    }

  else # Sketchup.version


    ### ERROR HANDLER ### ------------------------------------------------------

    require 'tt_truebend/vendor/heimdallr/error-reporter'

    # TT::Plugins::TrueBend::SETTINGS.error_server = 'sketchup.thomthom.local'
    # TT::Plugins::TrueBend::SETTINGS.error_server = 'sketchup.thomthom.net'
    server = SETTINGS.error_server

    config = {
      extension_id: EXTENSION[:product_id],
      extension:    @extension,
      server:       "http://#{server}/api/v1/extension/report_error",
      support_url:  'https://github.com/thomthom/true-bend',
      debug:        SETTINGS.debug?,
    }
    ERROR_REPORTER = ErrorReporter.new(config)


    ### Initialization ### -----------------------------------------------------

    begin
      require 'tt_truebend/main'
    rescue Exception => error
      ERROR_REPORTER.handle(error)
    end

  end # if Sketchup.version

end # module
