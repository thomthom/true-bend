#-------------------------------------------------------------------------------
#
# Thomas Thomassen
# thomas[at]thomthom[dot]net
#
#-------------------------------------------------------------------------------

# In case this file is loaded by Sketchup.require there won't be any reports of
# errors. Sketchup.require just silently return false which is very unhelpful.
# To aid in debugging this while file is wrapped in a begin;end block that
# capture everything and outputs to the Ruby Console.
begin

# There is no out of the box support for JSON on SketchUp 2013 and older which
# shipped only with the core of Ruby 1.8.
if RUBY_VERSION.to_i > 1
  require "json"
end


module TT::Plugins::TrueBend
  class ErrorReporter

    PLATFORM_OSX = (Object::RUBY_PLATFORM =~ /darwin/i) ? true : false
    PLATFORM_WIN = !PLATFORM_OSX

    HAS_EW_ID = Sketchup.version.to_i >= 13

    # @param [Hash] config
    # @option config [String] :extension_id
    # @option config [SketchupExtension] :extension
    # @option config [String] :server
    # @option config [String] :support_url
    # @option config [String] :debug (false)
    # @option config [String] :test (false) Set to true to log errors as test
    #                                       data in the database.
    # @param [String] library_path Path to the extension's support folder.
    #   If the extension is named `hello-world.rb` the support folder is the
    #   matching `hello-world` folder.
    def initialize(config, library_path)
      @extension_id = get_required_config(config, :extension_id)
      @extension    = get_required_config(config, :extension)
      @server       = get_required_config(config, :server)
      @debug        = get_optional_config(config, :debug, false)
      @test         = get_optional_config(config, :test, false)
      @support_url  = config[:support_url]
      @window       = nil
      @events       = {}
      @library_path = library_path
    rescue Exception => exception
      # Here we actually raise the exception because this happen during the
      # setup phase and should not be done as part of an exception handling.
      raise handle_unexpected_exception(exception)
    end

    # Pass the exception to the dialog, which afterwards re-raise it.
    #
    # @param [Exception] exception
    #
    # @return [Exception]
    def handle(exception)
      show_dialog(exception)
      raise exception
    end

    # Pass the exception to the dialog, without re-raising.
    #
    # @param [Exception] exception
    #
    # @return [Exception]
    def report(exception)
      show_dialog(exception)
    end


    protected


    # @param [String] event
    #
    # @return [Boolean]
    def on(event, &block)
      if block
        @events[event] ||= []
        @events[event] << block
        true
      else
        false
      end
    rescue Exception => exception
      handle_unexpected_exception(exception)
    end


    private


    # @return [String]
    def preference_key
      "Heimdallr"
    end

    # @return [String]
    def asset_path
      File.join(@library_path, 'error-reporter')
    end

    # @param [Hash] config
    # @param [Symbol] key
    #
    # @return [Mixed]
    def get_required_config(config, key)
      if config.key?(key)
        if config[key].nil?
          raise TypeError, "#{key} cannot be nil"
        else
          config[key]
        end
      else
        raise ArgumentError, "#{key} required"
      end
    end

    # @param [Hash] config
    # @param [Symbol] key
    # @param [Mixed] default
    #
    # @return [Mixed]
    def get_optional_config(config, key, default)
      if config.key?(key)
        config[key]
      else
        default
      end
    end

    # @param [Exception] exception_to_handle
    #
    # @return [Boolean]
    def show_dialog(exception_to_handle)
      # Only one dialog can be created at a time. Otherwise errors in mouse
      # events or observers cause hundreds of dialogs popping up.
      # If another error occur while the error dialog is open the error is
      # simply re-raised.
      return false if @window && @window.visible?
      @window = create_dialog(@extension_id, @extension)
      on("dialog_ready") { |dialog, data|
        setup_error_data(dialog, exception_to_handle)
        dialog = nil
      }
      # It's necessary to hold on to a reference to the UI::WebDialog.
      # Otherwise it'll close if the garbage collector kicks in while it's
      # open.
      if PLATFORM_OSX
        @window.show_modal
      else
        @window.show
      end
      true
    rescue Exception => exception
      handle_unexpected_exception(exception)
    end

    # @param [UI::WebDialog] window
    # @param [Exception] exception
    #
    # @return [Nil]
    def setup_error_data(window, exception)
      error_data = {
        :config => {
          :server => @server,
          :support_url => @support_url,
          :debug => @debug
        },

        :test => @test,

        :extension => {
          :id => @extension_id,
          :extension_warehouse_id => HAS_EW_ID ? @extension.id : '',
          :name => @extension.name,
          :version => @extension.version
        },

        :exception => {
          :inspect => exception.inspect,
          :type => exception.class.name,
          :message => exception.message,
          :backtrace => exception.backtrace # TODO: Ruby 1.8 stack trace different?
        },

        :environment => {
          :sketchup => {
            :version => Sketchup.version,
            :is_pro => sketchup_is_pro? ? 1 : 0, # `true` is POSTed as 0...
            :product_family => sketchup_product_family,
            :is_64bit => sketchup_is_64bit? ? 1 : 0,
            :locale => Sketchup.get_locale,
            :platform => sketchup_platform.to_s
          },
          :ruby => {
            :version => RUBY_VERSION,
            :platform => RUBY_PLATFORM,
            :patch_level => defined?(RUBY_PATCHLEVEL) ? RUBY_PATCHLEVEL : 0
          },
          :loaded_features => get_utf8_list(loaded_features) || [],
          :load_path => get_utf8_list($LOAD_PATH) || []
        }
      }
      call(window, "setup_error_data", error_data)
      nil
    end

    # @param [UI::WebDialog] window
    # @param [String] function
    #
    # @return [Nil]
    def call(window, function, *arguments)
      if window.nil? || !window.visible?
        raise RuntimeError, "Window must be visible before making calls to it"
      end
      json_arguments = arguments.map { |argument| json(argument) }
      js_arguments = json_arguments.join(", ")
      js_command = "#{function}(#{js_arguments});"
      window.execute_script(js_command)
      true
    end

    def loaded_features
      # It appear that older SketchUp versions return `nil` for
      # `$LOADED_FEATURES` and instead populate `$loaded_files`. However, it
      # also appear that `$loaded_files` isn't complete and updates during the
      # session. Might want to remove this as it looks to be rather irrelevant.
      $LOADED_FEATURES || $loaded_files
    end

    # @param [Hash] options
    #
    # @return [UI::WebDialog]
    def new_webdialog(options)
      if Sketchup.version.to_i < 7
        arguments = [
          options[:dialog_title],
          options[:scrollable],
          options[:preferences_key],
          options[:width],
          options[:height],
          options[:left],
          options[:top],
          options[:resizable]
        ]
        UI::WebDialog.new(*arguments)
      else
        UI::WebDialog.new(options)
      end
    end

    # @param [String] extension_id
    # @param [SketchupExtension] extension
    #
    # @return [UI::WebDialog]
    def create_dialog(extension_id, extension)
      options = {
        :dialog_title     => "#{extension.name} Error Report",
        :preferences_key  => extension_id,
        :resizable        => false,
        :scrollable       => false,
        :left             => 400,
        :top              => 400,
        :width            => 450,
        :height           => 580
      }
      window = new_webdialog(options)

      # Hide the navigation buttons that appear on OSX.
      if window.respond_to?(:navigation_buttons_enabled=)
        window.navigation_buttons_enabled = false
      end

      # OSX has a bug where it ignores the resize flag and let the user resize
      # the window. Setting the min and max values for width and height works
      # around this issue.
      #
      # To make things worse, OSX sets the client size with the min/max
      # methods - causing the window to grow if you set the min size to the
      # desired target size. To account for this we set the min sizes to be
      # a little less that the desired width. The size should be larger than
      # the titlebar height.
      #
      # All this has to be done before we set the size in order to restore the
      # desired size because the min/max methods will transpose the external
      # size to content size.
      #
      # The result is that the height is adjustable a little bit, but at least
      # it's restrained to be close to the desired size. Lesser evil until
      # this is fixed in SketchUp.
      if window.respond_to?(:min_width)
        # These methods where added in SU7.
        window.min_width = options[:width]
        window.max_width = options[:width]
        window.min_height = options[:height] - 30
        window.max_height = options[:height]
      end
      window.set_size(options[:width], options[:height])

      # Hook up callback bridge.
      window.add_action_callback("callback") { |dialog, event_name|
        #puts "Callback: 'callback(#{event_name})'"
        json = dialog.get_element_value("SU_BRIDGE")
        if json && json.size > 0
          data = parse_json(json)
        else
          data = nil
        end
        trigger_event(event_name, data)
        # Prevent circular references the would prevent the object from being
        # collected by the GC.
        event_name = data = dialog = nil
      }

      on("open_url") { |dialog, data|
        UI.openURL(data["url"])
        dialog = data = nil
      }

      on("dialog_ready") { |dialog, data|
        section = preference_key
        user_data = {
          :user_name => Sketchup.read_default(section, "name",  ""),
          :user_email => Sketchup.read_default(section, "email", "")
        }
        call(dialog, "restore_form", user_data)
        dialog = data = nil
      }

      on("save_and_close") { |dialog, data|
        section = preference_key
        Sketchup.write_default(section, "name",  data["name"].to_s)
        Sketchup.write_default(section, "email", data["email"].to_s)
        dialog.close
        dialog = data = nil
      }

      # Cannot rely on __FILE__ or __dir__ to resolve paths due to issues with
      # older SketchUp versions and RBS files. In newer versions __FILE__ will
      # work, but __dir__ wont. Additionally, __FILE__ have encoding bugs under
      # windows. So the encoding would have to be forced to account for this.
      # TODO: Consider checking the encoding of the passed in path and attempt
      # to fix it if possible.
      html_file =File.join(asset_path, "error-reporter.html")
      raise "#{html_file} not found" unless File.exist?(html_file)
      window.set_file(html_file)
      window
    end

    # @param [String] event
    # @param [JSON] data
    #
    # @return [Boolean]
    def trigger_event(event, data = nil)
      if @events.key?(event)
        @events[event].each { |callback|
          if data
            callback.call(@window, data)
          else
            callback.call(@window)
          end
        }
        true
      else
        false
      end
    rescue Exception => exception
      handle_unexpected_exception(exception)
    end

    # @return [Boolean]
    def sketchup_is_64bit?
      Sketchup.respond_to?(:is_64bit?) && Sketchup.is_64bit?
    end

    # @return [Boolean]
    def sketchup_is_pro?
      if Sketchup.respond_to?(:is_pro?)
        Sketchup.is_pro?
      else
        # Sketchup.is_pro? was added in SU7.
        Sketchup.app_name.include?('Pro')
      end
    end

    # For some reason +get_product_family+ was incorrectly placed on the
    # Sketchup::Model class - which means it will not be possible to access
    # if there are no models open under OSX.
    #
    # @return [Integer]
    def sketchup_product_family
      model = Sketchup.active_model
      if model && model.respond_to?(:get_product_family)
        model.get_product_family
      else
        0 # Unknown
      end
    end

    # @return [Symbol]
    def sketchup_platform
      return Sketchup.platform if Sketchup.respond_to?(:platform)
      PLATFORM_WIN ? :platform_win : :platform_osx
    end

    # @param [Array<String>]
    #
    # @return [String]
    def get_utf8_list(enumerator)
      return enumerator if enumerator.nil?
      enumerator.dup.map { |path|
        string = path.dup
        if string.respond_to?(:encode)
          begin
            string.encode("UTF-8")
          rescue
            # Under Windows there are multiple strings relating to files that
            # can have the incorrect encoding applied. They appear to generally
            # be UTF-8 data with the wrong encoding label. To account for this we
            # assume that any transcoding error to UTF-8 is a result of
            # mis-labelled UTF-8 strings and then fall back to forcing the
            # encoding.
            string.force_encoding("UTF-8")
          end
        end
        string
      }
    end

    # Handling errors in the error handler - how meta!
    #
    # Because this would happen when we are setting up the dialog when handling
    # an existing exception we simply output these errors to the console so
    # the user sees that something happened. Hopefully the user will report the
    # problem back to the developer.
    #
    # @param [Exception] exception
    #
    # @return [Exception]
    def handle_unexpected_exception(exception)
      SKETCHUP_CONSOLE.show if SKETCHUP_CONSOLE.respond_to?(:show)
      p exception
      puts exception.backtrace.join("\n")
      exception
    end

    # Converts a Hash to an escaped JSON string.
    #
    # @param [Hash] hash
    #
    # @return [String]
    def json(hash)
      return hash.to_json if defined?(JSON)
      # Fallback for older SketchUp version with Ruby 1.8 without StdLib.
      str = '{'
      arr = hash.to_a.map!{ |k,v|
        key = k.is_a?(Symbol) ? k.to_s.inspect : k.inspect
        if v.is_a?(Hash)
          "#{key}: #{json(v)}"
        else
          value = v.nil? ? "null" : v.inspect
          "#{key}: #{value}"
        end
      }
      str << arr.join(',')
      str << '}'
      str
    end

    # @param [String] hash
    #
    # @return [Hash]
    def parse_json(json_string)
      return JSON.parse(json_string) if defined?(JSON)
      # Naive fallback for older SketchUp versions that had only Ruby 1.8
      # without StdLib.
      eval(json_string.gsub('":"', '"=>"'))
    end

  end # class
end # module

rescue Exception => exception
  # Make sure to pop open the Ruby Console so this can be seen. Otherwise the
  # message will just disappear into the void.
  SKETCHUP_CONSOLE.show if defined?(SKETCHUP_CONSOLE)
  # Output a message to the user with information about what went wrong.
  puts "Something when wrong trying to load #{__FILE__}."
  puts "Please copy this message and forward it to the developer."
  p error
  puts error.backtrace
  # In case the file is loaded by require, or Sketchup.require stops eating
  # exceptions - reraise.
  raise
end # begin
