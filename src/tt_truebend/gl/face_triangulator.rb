require 'tt_truebend/gl/preview_triangle'
require 'tt_truebend/helpers/instance'

module TT::Plugins::TrueBend
  # Converts the faces of an instance to the triangles of the preview of the
  # bend.
  class FaceTriangulator

    include InstanceHelper

    # The `Sketchup::Face#mesh` flag for a mesh with vertex normals. Older
    # SketchUp versions have no constant for it.
    MESH_NORMALS = if defined?(Geom::PolygonMesh::MESH_NORMALS)
                     Geom::PolygonMesh::MESH_NORMALS
                   else
                     4
                   end

    # @param [FaceColors] face_colors
    def initialize(face_colors)
      @face_colors = face_colors
    end

    # Triangulates the faces that SketchUp shows of the instance and of the
    # instances nested in it. It relies on
    # `Sketchup::Model#drawing_element_visible?`, which was added in SketchUp
    # 2020.
    #
    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Geom::Transformation] transformation Converts the coordinates
    #   the instance is placed in to the coordinates of the triangles.
    # @return [Array<PreviewTriangle>]
    def triangles(instance, transformation = IDENTITY)
      triangles = []
      instance_path = (instance.model.active_path || []) + [instance]
      add_instance(triangles, instance_path, transformation, nil)
      triangles
    end

    # Splits the triangles along planes that are perpendicular to the X axis,
    # so that no triangle crosses a plane.
    #
    # @param [Array<PreviewTriangle>] triangles
    # @param [Array<Length, Float>] plane_positions The X coordinates of the
    #   planes, in ascending order.
    # @return [Array<PreviewTriangle>]
    def slice(triangles, plane_positions)
      # A `Length` is compared with SketchUp's tolerance when it is the
      # receiver of the comparison. A plane that only touches a triangle then
      # doesn't split it.
      plane_positions = plane_positions.map(&:to_l)
      sliced = []
      triangles.each { |triangle|
        polygon = triangle.vertices
        x_min, x_max = polygon.map(&:x).minmax
        index = plane_positions.bsearch_index { |plane_x| plane_x > x_min }
        while index && index < plane_positions.size && plane_positions[index] < x_max
          before, polygon = split(polygon, plane_positions[index])
          add_triangle_fan(sliced, before, triangle)
          index += 1
        end
        add_triangle_fan(sliced, polygon, triangle)
      }
      sliced
    end

    private

    # @param [Array<PreviewTriangle>] triangles The triangles of the instance
    #   are appended to this.
    # @param [Array<Sketchup::Drawingelement>] instance_path The instance,
    #   preceded by the instances it is nested in.
    # @param [Geom::Transformation] transformation Converts the coordinates
    #   the instance is placed in to the coordinates of the triangles.
    # @param [FaceColors::Inherited, nil] inherited What the instance inherits
    #   from the instance it is nested in.
    def add_instance(triangles, instance_path, transformation, inherited)
      instance = instance_path.last
      model = instance.model
      inherited = @face_colors.inherit(instance, inherited)
      transformation *= instance.transformation
      face_path = instance_path + [nil]
      definition(instance).entities.each { |entity|
        if entity.is_a?(Sketchup::Face)
          # Only faces are tested, because the method raises for a path that
          # ends in an instance before SketchUp 2026. A face in a hidden
          # instance is reported as not visible.
          face_path[-1] = entity
          # rubocop:disable-next SketchupSuggestions/Compatibility
          next unless model.drawing_element_visible?(face_path)

          add_face(triangles, entity, transformation, inherited)
        elsif instance?(entity)
          add_instance(triangles, instance_path + [entity], transformation, inherited)
        end
      }
    end

    # @param [Array<PreviewTriangle>] triangles The triangles of the face are
    #   appended to this.
    # @param [Sketchup::Face] face
    # @param [Geom::Transformation] transformation
    # @param [FaceColors::Inherited] inherited
    def add_face(triangles, face, transformation, inherited)
      mesh = face.mesh(MESH_NORMALS)
      # This keeps the normals perpendicular to the faces, also when the
      # transformation scales non-uniformly or mirrors.
      mesh.transform!(transformation)
      vertices = mesh.points.each_with_index.map { |point, index|
        # Mesh indices start at 1.
        PreviewVertex.from_geom(point, mesh.normal_at(index + 1))
      }
      front_color, back_color = @face_colors.colors_of(face, inherited)
      mesh.polygons.each { |polygon|
        # A negative index marks an edge of the polygon as hidden.
        corners = polygon.map { |index| vertices[index.abs - 1] }
        triangles << PreviewTriangle.new(corners, front_color, back_color)
      }
    end

    # Splits a convex polygon along a plane that is perpendicular to the X
    # axis.
    #
    # @param [Array<PreviewVertex>] polygon
    # @param [Length] plane_x The X coordinate of the plane.
    # @return [Array(Array<PreviewVertex>, Array<PreviewVertex>)] The part of
    #   the polygon before the plane and the part after it, along the X axis.
    #   A part has fewer than three vertices when the polygon doesn't cross
    #   the plane.
    def split(polygon, plane_x)
      before = []
      after = []
      polygon.each_with_index { |vertex, index|
        next_vertex = polygon[(index + 1) % polygon.size]
        offset = vertex.x - plane_x
        next_offset = next_vertex.x - plane_x
        before << vertex if offset <= 0.0
        after << vertex if offset >= 0.0
        edge_crosses_plane = offset * next_offset < 0.0
        next unless edge_crosses_plane

        crossing = vertex.interpolate(next_vertex, offset / (offset - next_offset))
        before << crossing
        after << crossing
      }
      [before, after]
    end

    # Triangulates a convex polygon as a triangle fan.
    #
    # @param [Array<PreviewTriangle>] triangles The triangles of the polygon
    #   are appended to this.
    # @param [Array<PreviewVertex>] polygon
    # @param [PreviewTriangle] source The triangle the polygon is a part of,
    #   which the new triangles take their colours from.
    def add_triangle_fan(triangles, polygon, source)
      polygon.drop(1).each_cons(2) { |second, third|
        corners = [polygon.first, second, third]
        triangles << PreviewTriangle.new(corners, source.front_color, source.back_color)
      }
    end

  end # class
end # module
