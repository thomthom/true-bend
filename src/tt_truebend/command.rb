require 'tt_truebend/resource'

module TT::Plugins::TrueBend
  module UICommand

    # SketchUp allocate the object by implementing `new` - probably part of
    # older legacy implementation when that was the norm. Because of that the
    # class cannot be sub-classed directly. This module simulates the interface
    # for how UI::Command is created. `new` will create an instance of
    # UI::Command but mix itself into the instance - effectively subclassing it.
    # (yuck!)
    #
    # @param [String] title
    # @param [Proc] block
    def self.new(title, &block)
      command = UI::Command.new(title) {
        begin
          block.call
        rescue Exception => exception
          ERROR_REPORTER.handle(exception)
        end
      }
      command.extend(self)
      command
    end

    # Automatically sets the large and small icon, assuming a file convention.
    #
    # If `path` is "path/to/file.png" then this method will assume and assign the
    # following file paths to small and large icons:
    # - "path/to/file-24.png"
    # - "path/to/file-32.png"
    #
    # @param [String] path
    def icon=(path)
      basename = File.basename(path, '.*')
      extname = File.extname(path)
      dirname = File.dirname(path)
      self.small_icon = File.join(dirname, "#{basename}-24#{extname}")
      self.large_icon = File.join(dirname, "#{basename}-32#{extname}")
    end

    # Sets the large icon for the command. Provide the full path to the raster
    # image and the method will look for a vector variant in the same folder
    # with the same basename.
    #
    # @param [String] path
    def large_icon=(path)
      super(Resource.get_icon_path(path))
    end

    # @see #large_icon
    #
    # @param [String] path
    def small_icon=(path)
      super(Resource.get_icon_path(path))
    end

  end # module
end # module
