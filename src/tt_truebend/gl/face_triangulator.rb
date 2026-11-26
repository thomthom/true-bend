require 'tt_truebend/helpers/instance'

module TT::Plugins::TrueBend
  # Converts the faces of an instance to triangles, for drawing a preview of
  # the faces.
  #
  # A triangle is an Array of three vertices followed by the colours
  # {FaceColors#colors} returns for its face. A vertex is an Array of six
  # Floats: the position followed by the normal.
  class FaceTriangulator

    include InstanceHelper

    # A triangle is not cut by a plane that is closer than this to its
    # outermost vertex.
    TOLERANCE = 1.0e-9

    # The flag that makes `Sketchup::Face#mesh` include the normals.
    MESH_NORMALS = 4

    # @param [FaceColors] colors
    def initialize(colors)
      @colors = colors
    end

    # The faces of the instance and of the instances inside it that SketchUp
    # shows. This relies on `Sketchup::Model#drawing_element_visible?`, which
    # SketchUp has from version 2020.
    #
    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Geom::Transformation] transformation The transformation from the
    #   coordinates the instance is placed in to the coordinates of the
    #   triangles.
    # @return [Array<Array>]
    def triangles(instance, transformation = IDENTITY)
      result = []
      path = (instance.model.active_path || []) + [instance]
      collect(path, transformation, nil, result)
      result
    end

    # Cuts the triangles along planes that are perpendicular to the X axis.
    #
    # @param [Array<Array>] triangles
    # @param [Array<Float>] cuts The X coordinates of the planes, in ascending
    #   order.
    # @return [Array<Array>]
    def slice(triangles, cuts)
      result = []
      triangles.each { |triangle|
        polygon = triangle[0, 3]
        colors = triangle[3]
        min, max = [polygon[0][0], polygon[1][0], polygon[2][0]].minmax
        index = (0...cuts.size).bsearch { |i| cuts[i] > min + TOLERANCE }
        while index && index < cuts.size && cuts[index] < max - TOLERANCE
          before, polygon = split(polygon, cuts[index])
          fan(before, colors, result)
          index += 1
        end
        fan(polygon, colors, result)
      }
      result
    end

    private

    # @param [Array<Sketchup::Drawingelement>] path The instance to collect
    #   the faces of, preceded by the instances it is inside of.
    # @param [Geom::Transformation] transformation
    # @param [Array, nil] inherited See {FaceColors#inherit}.
    # @param [Array<Array>] result The triangles are added to this.
    def collect(path, transformation, inherited, result)
      instance = path.last
      model = instance.model
      inherited = @colors.inherit(instance, inherited)
      to_target = transformation * instance.transformation
      normals_to_target = normal_transformation(to_target)
      face_path = path + [nil]
      definition(instance).entities.each { |entity|
        if entity.is_a?(Sketchup::Face)
          # Before SketchUp 2026 the path cannot end in an instance, so the
          # visibility of an instance is found from its faces. The faces are
          # only collected in SketchUp 2020 and later, which have the method.
          face_path[-1] = entity
          # rubocop:disable-next SketchupSuggestions/Compatibility
          next unless model.drawing_element_visible?(face_path)

          add_face(entity, to_target, normals_to_target, inherited, result)
        elsif instance?(entity)
          collect(path + [entity], to_target, inherited, result)
        end
      }
    end

    # @param [Sketchup::Face] face
    # @param [Geom::Transformation] transformation
    # @param [Geom::Transformation] normal_transformation
    # @param [Array, nil] inherited See {FaceColors#inherit}.
    # @param [Array<Array>] result The triangles are added to this.
    def add_face(face, transformation, normal_transformation, inherited, result)
      mesh = face.mesh(MESH_NORMALS)
      vertices = mesh.points.each_with_index.map { |point, index|
        normal = mesh.normal_at(index + 1).transform(normal_transformation)
        point.transform(transformation).to_a.map(&:to_f) + normal.to_a
      }
      colors = @colors.colors(face, inherited)
      mesh.polygons.each { |polygon|
        # A negative index marks an edge of the polygon as hidden.
        a, b, c = polygon.map { |index| vertices[index.abs - 1] }
        result << [a, b, c, colors]
      }
    end

    # A normal stays perpendicular to its face only if it is transformed by
    # the inverse transpose of the transformation of the face. That is another
    # transformation when the face is scaled non-uniformly.
    #
    # @param [Geom::Transformation] transformation
    # @return [Geom::Transformation]
    def normal_transformation(transformation)
      m = transformation.inverse.to_a
      transposed = [
        m[0], m[4], m[8],  0.0,
        m[1], m[5], m[9],  0.0,
        m[2], m[6], m[10], 0.0,
        0.0,  0.0,  0.0,   1.0,
      ]
      Geom::Transformation.new(transposed)
    end

    # @param [Array<Array<Float>>] polygon Vertices of a convex polygon.
    # @param [Float] cut The X coordinate to split the polygon at.
    # @return [Array(Array, Array)] The parts of the polygon before and after
    #   the cut. A part has fewer than three vertices when the polygon doesn't
    #   reach across the cut.
    def split(polygon, cut)
      before = []
      after = []
      polygon.each_with_index { |vertex, index|
        following = polygon[(index + 1) % polygon.size]
        offset = vertex[0] - cut
        following_offset = following[0] - cut
        before << vertex if offset <= 0.0
        after << vertex if offset >= 0.0
        next unless offset * following_offset < 0.0

        ratio = offset / (offset - following_offset)
        crossing = Array.new(6) { |i| vertex[i] + ((following[i] - vertex[i]) * ratio) }
        crossing[0] = cut
        before << crossing
        after << crossing
      }
      [before, after]
    end

    # @param [Array<Array<Float>>] polygon Vertices of a convex polygon.
    # @param [Array<Sketchup::Color>] colors
    # @param [Array<Array>] result The triangles are added to this.
    def fan(polygon, colors, result)
      (1...(polygon.size - 1)).each { |index|
        result << [polygon[0], polygon[index], polygon[index + 1], colors]
      }
    end

  end # class
end # module
