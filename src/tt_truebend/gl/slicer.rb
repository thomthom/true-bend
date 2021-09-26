require 'tt_truebend/geom/segment'
require 'tt_truebend/helpers/instance'


module TT::Plugins::TrueBend
  class Slicer

    include InstanceHelper

    def initialize(planes = [])
      @planes = planes
    end

    # The planes should be in world coordinates.
    def add_plane(plane)
      @planes << plane
    end

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    #
    # @yield [edge]
    #   @yieldparam [Sketchup::Edge] edge
    def slice(instance, &block)
      entities = definition(instance).entities

      # The slicing group is created as a sibling to the instance being sliced.
      # Don't want to create it inside the instance being sliced as it should
      # not intersect itself.
      # `instance.parent` will be either `Model` or `ComponentDefinition`.
      slice_group = instance.parent.entities.add_group

      # Create faces slicing through the instance. The faces are made large
      # enough to fully intersect the instance.
      bounds = BoundingBoxWidget.new(instance)
      n = bounds.diagonal
      w = bounds.diagonal * 3
      quad = [
        Geom::Point3d.new(-n,     -n,     0),
        Geom::Point3d.new(-n + w, -n,     0),
        Geom::Point3d.new(-n + w, -n + w, 0),
        Geom::Point3d.new(-n,     -n + w, 0),
      ]
      @planes.each { |plane|
        plane_origin = plane[0]
        plane_normal = plane[1]
        tr = Geom::Transformation.new(plane_origin, plane_normal)
        points = quad.map { |pt| pt.transform(tr) }
        slice_group.entities.add_face(points)
      }

      # Intersect the entities in the instance with the slicing planes.
      transformation = instance.transformation
      plane_entities = slice_group.entities
      intersect_planes(entities, transformation, plane_entities, &block)

      slice_group.erase!
    end

    def segment_points(entities, transformation = IDENTITY)
      original_segments = edge_segments(entities, transformation)
      segments = slice_segments(original_segments, @planes)
      points = segments.map(&:points).flatten
      # Child instances:
      entities.each { |entity|
        next unless instance?(entity)

        tr = transformation * entity.transformation
        points.concat(segment_points(definition(entity).entities, tr))
      }
      points
    end

    private

    # @param [Sketchup::Entities] enities
    # @param [Geom::Transformation] transformation
    # @param [Array<Sketchup::Entity>] plane_entities
    #
    # @yield [edge]
    #   @yieldparam [Sketchup::Edge] edge
    def intersect_planes(entities, transformation, plane_entities, &block)
      # The new edges from the intersection is created in a temporary group so
      # it is possible to apply various properties to them. If the edges are
      # created directly in the definition then its not possible to determine
      # which are the intersecting edges and which were created as a result of
      # splitting an existing edge.
      temp = entities.add_group
      entities.intersect_with(
          false, # recurse - must be off for desired result.
          transformation,
          temp.entities, # target Entities collection
          transformation,
          false, # hidden
          plane_entities.to_a # Array of entities to intersect `entities` with.
      )
      temp.entities.grep(Sketchup::Edge, &block)
      temp.explode
      # Child instances:
      # The `recurse` parameter of `intersect_with` doesn't yield correct.
      # result. Undesired additional edges appear.
      # Instead we recurse manually.
      entities.each { |entity|
        next unless instance?(entity)

        entity.make_unique
        ents = definition(entity).entities
        tr = transformation * entity.transformation
        intersect_planes(ents, tr, plane_entities, &block)
      }
      nil
    end

    def edge_segments(entities, transformation, _wysiwyg: true)
      edges = entities.grep(Sketchup::Edge).reject { |edge|
        edge.hidden? || edge.soft? || !edge.layer.visible?
      }
      edges.map { |edge|
        segment = Segment.new(edge.start.position, edge.end.position)
        segment.transform!(transformation)
        segment
      }
    end

    def slice_segments(segments, planes)
      result = []
      stack = segments.dup
      planes.each { |plane|
        result = []
        stack.each { |segment|
          result.concat(segment.split(plane))
        }
        stack = result
      }
      result
    end

  end # class
end # module
