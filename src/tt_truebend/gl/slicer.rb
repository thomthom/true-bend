require 'tt_truebend/constants/view'
require 'tt_truebend/gl/drawing_helper'
require 'tt_truebend/geom/segment'

module TT::Plugins::TrueBend
  class Slicer

    include DrawingHelper
    include ViewConstants

    attr_accessor :transformation

    def initialize(instance)
      @instance = instance
      @planes = []
      @transformation = nil
    end

    def add_plane(plane)
      @planes << plane
    end

    def segment_points
      original_segments = edge_segments(@instance.definition.entities)
      segments = slice(original_segments, @planes)
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

    def slice(segments, planes)
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
