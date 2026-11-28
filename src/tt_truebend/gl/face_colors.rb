module TT::Plugins::TrueBend
  # Finds the colours that the style of a model draws faces in. Textures are
  # ignored: a textured material gives its `Sketchup::Material#color`.
  class FaceColors

    # Values of the "RenderMode" rendering option. The API documentation
    # doesn't list them. They were observed in SketchUp 2027.
    WIREFRAME = 0
    HIDDEN_LINE = 1
    MONOCHROME = 5

    # The material and the tag that the faces of an instance inherit from the
    # instance when they have none of their own.
    #
    # @!attribute material
    #   @return [Sketchup::Material, nil]
    # @!attribute layer
    #   @return [Sketchup::Layer, nil]
    Inherited = Struct.new(:material, :layer)

    # @param [Sketchup::Model] model
    # @param [Float] opacity The opacity an opaque face is given, from 0.0 to
    #   1.0. The alpha of a transparent material is multiplied by it.
    def initialize(model, opacity = 1.0)
      options = model.rendering_options
      @opacity = opacity
      @render_mode = options['RenderMode']
      @color_by_tag = options['DisplayColorByLayer']
      @material_transparency = options['MaterialTransparency']
      @untagged = model.layers[0]
      # Equal colours are the same object, so that a colour can be used as a
      # Hash key to group triangles by.
      @colors_by_rgba = {}
      @colors_by_source = {}
      @default_front_color = shared_color(options['FaceFrontColor'])
      @default_back_color = shared_color(options['FaceBackColor'])
      @background_color = shared_color(options['BackgroundColor'])
    end

    # @return [Boolean] Whether the style fills faces.
    def fill?
      @render_mode != WIREFRAME
    end

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Inherited, nil] inherited What the instance inherits from the
    #   instance it is nested in.
    # @return [Inherited] What the faces of the instance inherit.
    def inherit(instance, inherited = nil)
      material = instance.material || (inherited && inherited.material)
      layer = instance.layer == @untagged ? (inherited && inherited.layer) : instance.layer
      Inherited.new(material, layer)
    end

    # @param [Sketchup::Face] face
    # @param [Inherited, nil] inherited What the face inherits from the
    #   instance it is in.
    # @return [Array(Sketchup::Color, Sketchup::Color)] The colours of the
    #   front and the back of the face.
    def colors_of(face, inherited = nil)
      return [@background_color, @background_color] if @render_mode == HIDDEN_LINE
      return [@default_front_color, @default_back_color] if @render_mode == MONOCHROME

      inherited ||= Inherited.new
      if @color_by_tag
        layer = face.layer
        layer = inherited.layer if layer == @untagged && inherited.layer
        tag_color = (@colors_by_source[layer] ||= shared_color(layer.color))
        return [tag_color, tag_color]
      end
      front = face.material || inherited.material
      back = face.back_material || inherited.material
      [
        front ? material_color(front) : @default_front_color,
        back ? material_color(back) : @default_back_color,
      ]
    end

    private

    # @param [Sketchup::Material] material
    # @return [Sketchup::Color]
    def material_color(material)
      @colors_by_source[material] ||= begin
        alpha = @material_transparency ? material.alpha : 1.0
        shared_color(material.color, alpha)
      end
    end

    # @param [Sketchup::Color] color
    # @param [Float] alpha
    # @return [Sketchup::Color] The colour with the alpha and the opacity of
    #   the preview applied. The same object is returned for equal colours.
    def shared_color(color, alpha = 1.0)
      # Rounding down keeps the colour from being more opaque than asked for.
      rgba = [color.red, color.green, color.blue, (255 * alpha * @opacity).floor]
      @colors_by_rgba[rgba] ||= Sketchup::Color.new(*rgba)
    end

  end # class
end # module
