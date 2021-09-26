module TT::Plugins::TrueBend
  module Resource

    # The supported file format for vector icons depend on the platform.
    VECTOR_FILETYPE = Sketchup.platform == :platform_osx ? 'pdf' : 'svg'

    # @param [String] path
    # @return [String]
    def self.get_icon_path(path)
      return path unless Sketchup.version.to_i > 15

      vector_icon = self.get_vector_path(path)
      File.exist?(vector_icon) ? vector_icon : path
    end

    # @param [String] path
    # @return [String]
    def self.get_vector_path(path)
      dir = File.dirname(path)
      basename = File.basename(path, '.*')
      File.join(dir, "#{basename}.#{VECTOR_FILETYPE}")
    end

  end # module
end # module
