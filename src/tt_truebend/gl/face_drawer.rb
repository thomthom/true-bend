require 'tt_truebend/gl/preview_triangle'

module TT::Plugins::TrueBend
  # Draws the triangles of the preview of the bent faces.
  module FaceDrawer

    # The depth pre-pass is drawn this many pixels further from the camera
    # than the triangles are, which keeps the triangles from failing the
    # depth test against their own depth. A triangle less than this far behind
    # another one is not hidden by it.
    DEPTH_OFFSET_PIXELS = 0.5

    # Triangles in a fully transparent colour change no pixels, but their
    # depth is still written to the depth buffer. The colour is not black,
    # because `Sketchup::View#drawing_color=` ignores a fully transparent
    # black.
    DEPTH_ONLY_COLOR = Sketchup::Color.new(255, 255, 255, 0)

    # The triangles that are drawn in one colour.
    #
    # @!attribute points
    #   @return [Array<Geom::Point3d>] Three points for each triangle.
    # @!attribute normals
    #   @return [Array<Geom::Vector3d>] The vertex normal at each point.
    TriangleBatch = Struct.new(:points, :normals)

    # The triangles are shaded by their vertex normals, which
    # `Sketchup::View#draw` accepts from SketchUp 2020.
    #
    # @param [Integer] version The major version of SketchUp.
    # @return [Boolean]
    def self.supported?(version = Sketchup.version.to_i)
      version >= 20
    end

    private

    # Draws the triangles shaded. Anything that is drawn in model space after
    # them is hidden where it is behind one of them.
    #
    # @param [Sketchup::View] view
    # @param [Array<PreviewTriangle>] triangles
    # @param [Boolean] see_through Whether the triangles show through the
    #   triangles in front of them.
    def draw_triangles(view, triangles, see_through)
      front_facing, back_facing = batches_by_facing(triangles, view.camera)
      draw_depth_prepass(view, [back_facing, front_facing]) unless see_through
      # Transparent triangles are drawn back to front. On a closed shape the
      # back-facing triangles are behind the front-facing ones.
      draw_batches(view, back_facing)
      draw_batches(view, front_facing)
    end

    # Groups the triangles by the side of them that the camera sees, and by
    # the colour of that side.
    #
    # @param [Array<PreviewTriangle>] triangles
    # @param [Sketchup::Camera] camera
    # @return [Array(Hash, Hash)] The front-facing triangles and the
    #   back-facing triangles. Each is a `Hash{Sketchup::Color => TriangleBatch}`.
    def batches_by_facing(triangles, camera)
      front_facing = Hash.new { |batches, color| batches[color] = TriangleBatch.new([], []) }
      back_facing = Hash.new { |batches, color| batches[color] = TriangleBatch.new([], []) }
      eye = camera.eye
      # In a parallel projection every line of sight has the direction of the
      # camera.
      parallel_line_of_sight = camera.perspective? ? nil : camera.direction
      triangles.each { |triangle|
        face_normal = triangle.face_normal
        next unless face_normal.valid?

        line_of_sight = parallel_line_of_sight || eye.vector_to(triangle.vertices.first.position)
        batch = if face_normal % line_of_sight > 0.0
                  back_facing[triangle.back_color]
                else
                  front_facing[triangle.front_color]
                end
        batch.points.concat(triangle.positions)
        batch.normals.concat(triangle.normals)
      }
      [front_facing, back_facing]
    end

    # @param [Sketchup::View] view
    # @param [Hash{Sketchup::Color => TriangleBatch}] batches
    def draw_batches(view, batches)
      visible(batches).each { |color, batch|
        view.drawing_color = color
        view.draw(GL_TRIANGLES, batch.points, normals: batch.normals)
      }
    end

    # @param [Hash{Sketchup::Color => TriangleBatch}] batches
    # @return [Hash{Sketchup::Color => TriangleBatch}] The batches whose colour
    #   is not fully transparent.
    def visible(batches)
      batches.reject { |color, _| color.alpha == 0 }
    end

    # Draws the triangles in a fully transparent colour, slightly further from
    # the camera than they are. That changes no pixels, but writes the depth
    # of the triangles to the depth buffer. Of the triangles drawn afterwards,
    # only the parts nearest to the camera then pass the depth test, so the
    # far side of the preview doesn't show through the near side.
    #
    # A fully transparent triangle is left out, as it would hide the ones
    # behind it without being drawn itself.
    #
    # @param [Sketchup::View] view
    # @param [Array<Hash{Sketchup::Color => TriangleBatch}>] batches_by_facing
    def draw_depth_prepass(view, batches_by_facing)
      points = batches_by_facing.flat_map { |batches| visible(batches).values.flat_map(&:points) }
      return if points.empty?

      camera = view.camera
      # `Sketchup::View#pixels_to_model` rounds the number of pixels to an
      # integer, so the size of one pixel is scaled instead.
      offset = view.pixels_to_model(1, camera.target) * DEPTH_OFFSET_PIXELS
      return unless offset > 0.0

      if camera.perspective?
        # The size of a pixel is proportional to the distance from the camera,
        # so scaling about the camera moves every point by the same number of
        # pixels.
        scale = 1.0 + (offset / camera.eye.distance(camera.target))
        push_back = Geom::Transformation.scaling(camera.eye, scale)
      else
        translation = camera.direction
        translation.length = offset
        push_back = Geom::Transformation.translation(translation)
      end
      view.drawing_color = DEPTH_ONLY_COLOR
      view.draw(GL_TRIANGLES, points.map { |point| point.transform(push_back) })
    end

  end # module
end # module
