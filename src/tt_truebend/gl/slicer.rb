require 'tt_truebend/constants/view'
require 'tt_truebend/gl/drawing_helper'
require 'tt_truebend/geom/segment'

module TT::Plugins::TrueBend
  class Slicer

    include DrawingHelper
    include ViewConstants

    # Transformation applied to the result of `segment_points` to transform into
    # world coordinates.
    attr_accessor :transformation

    def initialize(instance)
      @instance = instance
      @planes = []
      @transformation = nil
    end

    # The planes should be in world coordinates.
    def add_plane(plane)
      @planes << plane
    end

    def slice
      entities = @instance.definition.entities

      # The slicing group is created as a sibling to the instance being sliced.
      # Don't want to create it inside the instance being sliced as it should
      # not intersect itself.
      slice_group = @instance.parent.entities.add_group

      # Create faces slicing through the instance. The faces are made large
      # enough to fully intersect the instance.
      bounds = BoundingBoxWidget.new(@instance)
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

      # The new edges from the intersection is created in a temporary group so
      # it is possible to apply various properties to them. If the edges are
      # created directly in the definition then its not possible to determine
      # which are the intersecting edges and which were created as a result of
      # splitting an existing edge.
      temp = entities.add_group
      entities.intersect_with(
        false,
        @instance.transformation,
        temp.entities,
        @instance.transformation,
        false,
        slice_group.entities.to_a
      )
      temp.entities.grep(Sketchup::Edge) { |edge| yield edge }
      temp.explode

      slice_group.erase!
    end

    def segment_points
      original_segments = edge_segments(@instance.definition.entities)
      segments = slice_segments(original_segments, @planes)
      segments.map(&:points).flatten
    end

    def draw(view)
      points = lift!(view, segment_points, pixels: 1)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = 2
      view.drawing_color = 'maroon'
      view.draw(GL_LINES, points)
      view.draw_points(points, 6, DRAW_FILLED_SQUARE, 'maroon')
    end

    private

    def edge_segments(entities, wysiwyg: true)
      edges = entities.grep(Sketchup::Edge).reject { |edge|
        edge.hidden? || edge.soft? || !edge.layer.visible?
      }
      edges.map { |edge|
        segment = Segment.new(edge.start.position, edge.end.position)
        segment.transform!(@transformation) if @transformation
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
