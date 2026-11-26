module TT::Plugins::TrueBend
  # The colours the style of a model gives to faces, for drawing a preview of
  # the faces. Textures are not taken into account: a textured material gives
  # the colour `Sketchup::Material#color` returns for it.
  class FaceColors

    # Values of the "RenderMode" rendering option. The API documentation does
    # not list them. They were observed in SketchUp 2027.
    WIREFRAME = 0
    HIDDEN_LINE = 1
    MONOCHROME = 5

    # @param [Sketchup::Model] model
    # @param [Float] opacity The opacity to draw an opaque face with, from 0.0
    #   to 1.0. A transparent material is drawn more transparent in proportion.
    def initialize(model, opacity = 1.0)
      options = model.rendering_options
      @opacity = opacity
      @mode = options['RenderMode']
      @by_layer = options['DisplayColorByLayer']
      @transparency = options['MaterialTransparency']
      @untagged = model.layers[0]
      # Equal colours share one object, so that triangles can be grouped by
      # colour with the colour as a Hash key.
      @colors = {}
      @sources = {}
      @front = color(options['FaceFrontColor'])
      @back = color(options['FaceBackColor'])
      @background = color(options['BackgroundColor'])
    end

    # @return [Boolean] Whether the style fills faces.
    def fill?
      @mode != WIREFRAME
    end

    # What the faces of an instance get from the instance when they have no
    # material or tag of their own.
    #
    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Array(Sketchup::Material, Sketchup::Layer), nil] inherited What
    #   the instance gets from the instance it is in.
    # @return [Array(Sketchup::Material, Sketchup::Layer)]
    def inherit(instance, inherited = nil)
      material, layer = inherited
      layer = instance.layer unless instance.layer == @untagged
      [instance.material || material, layer]
    end

    # @param [Sketchup::Face] face
    # @param [Array(Sketchup::Material, Sketchup::Layer), nil] inherited See
    #   {#inherit}.
    # @return [Array(Sketchup::Color, Sketchup::Color)] The colours of the
    #   front and the back of the face.
    def colors(face, inherited = nil)
      return [@background, @background] if @mode == HIDDEN_LINE
      return [@front, @back] if @mode == MONOCHROME

      material, layer = inherited
      if @by_layer
        layer = face.layer unless layer && face.layer == @untagged
        tag_color = (@sources[layer] ||= color(layer.color))
        return [tag_color, tag_color]
      end
      front = face.material || material
      back = face.back_material || material
      [front ? material_color(front) : @front, back ? material_color(back) : @back]
    end

    private

    # @param [Sketchup::Material] material
    # @return [Sketchup::Color]
    def material_color(material)
      @sources[material] ||= color(material.color, @transparency ? material.alpha : 1.0)
    end

    # @param [Sketchup::Color] color
    # @param [Float] alpha
    # @return [Sketchup::Color]
    def color(color, alpha = 1.0)
      # Rounding down keeps the colour from being more opaque than asked for.
      rgba = [color.red, color.green, color.blue, (255 * alpha * @opacity).floor]
      @colors[rgba] ||= Sketchup::Color.new(*rgba)
    end

  end # class
end # module
