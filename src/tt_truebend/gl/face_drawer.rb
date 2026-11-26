module TT::Plugins::TrueBend
  # Draws the triangles of a preview of faces.
  module FaceDrawer

    # How far the depth pass of the faces is moved away from the camera, in
    # pixels. A face that is closer than this behind another one is drawn as
    # well. With a much smaller value the faces fail the depth test against
    # their own depth.
    DEPTH_OFFSET_PIXELS = 0.5

    # A colour that leaves the pixels unchanged and still writes their depth.
    # `Sketchup::View#drawing_color=` ignores a fully transparent black.
    DEPTH_ONLY_COLOR = Sketchup::Color.new(255, 255, 255, 0)

    # `Sketchup::View#draw` takes vertex normals from SketchUp 2020. Without
    # them the faces cannot be shaded.
    #
    # @param [Integer] version The major version of SketchUp.
    # @return [Boolean]
    def self.supported?(version = Sketchup.version.to_i)
      version >= 20
    end

    private

    # Draws shaded triangles. They write to the depth buffer, so anything drawn
    # after them is hidden where it is behind them.
    #
    # @param [Sketchup::View] view
    # @param [Array<Array>] triangles See {PolarProjection#project_triangles}.
    #   The value passed through with each triangle is the colours of its
    #   front and back.
    # @param [Boolean] see_through Whether the triangles behind other
    #   triangles are drawn.
    def draw_triangles(view, triangles, see_through)
      front, back = triangle_batches(triangles, view.camera)
      draw_triangle_depth(view, triangles) unless see_through
      # A transparent triangle hides the ones drawn after it that are behind
      # it. The ones that face away from the camera are behind the others on a
      # closed shape.
      draw_triangle_batches(view, back)
      draw_triangle_batches(view, front)
    end

    # Groups the triangles by the side of them that faces the camera, and by
    # the colour of that side.
    #
    # @param [Array<Array>] triangles
    # @param [Sketchup::Camera] camera
    # @return [Array(Hash, Hash)] The triangles seen from the front and the
    #   ones seen from the back. Each Hash has the points and the normals of
    #   the triangles by colour.
    def triangle_batches(triangles, camera)
      batches = [{}, {}]
      eye = camera.eye
      to_camera = camera.perspective? ? nil : camera.direction.reverse
      triangles.each { |points, normals, colors|
        face_normal = (points[1] - points[0]) * (points[2] - points[0])
        next unless face_normal.valid?

        side = face_normal % (to_camera || points[0].vector_to(eye)) < 0.0 ? 1 : 0
        batch = (batches[side][colors[side]] ||= [[], []])
        batch[0].concat(points)
        batch[1].concat(normals)
      }
      batches
    end

    # @param [Sketchup::View] view
    # @param [Hash{Sketchup::Color => Array}] batches
    def draw_triangle_batches(view, batches)
      batches.each { |color, (points, normals)|
        next if color.alpha == 0

        view.drawing_color = color
        view.draw(GL_TRIANGLES, points, normals: normals)
      }
    end

    # Writes the depth of the triangles without drawing them, slightly further
    # from the camera than they are. Of the triangles drawn afterwards, only
    # the ones nearest to the camera then pass the depth test.
    #
    # @param [Sketchup::View] view
    # @param [Array<Array>] triangles
    def draw_triangle_depth(view, triangles)
      points = triangles.flat_map(&:first)
      return if points.empty?

      camera = view.camera
      # `Sketchup::View#pixels_to_model` rounds the number of pixels.
      offset = view.pixels_to_model(1, camera.target) * DEPTH_OFFSET_PIXELS
      return unless offset > 0.0

      if camera.perspective?
        # The size of a pixel is proportional to the distance in front of the
        # camera, so scaling about the camera moves every point by the same
        # number of pixels.
        ratio = offset / camera.eye.distance(camera.target)
        away = Geom::Transformation.scaling(camera.eye, 1.0 + ratio)
      else
        vector = camera.direction
        vector.length = offset
        away = Geom::Transformation.translation(vector)
      end
      view.drawing_color = DEPTH_ONLY_COLOR
      view.draw(GL_TRIANGLES, points.map { |point| point.transform(away) })
    end

  end # module
end # module
