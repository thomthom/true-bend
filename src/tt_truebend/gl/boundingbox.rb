require 'tt_truebend/constants/boundingbox'
require 'tt_truebend/constants/view'
require 'tt_truebend/helpers/boundingbox'
require 'tt_truebend/helpers/instance'
require 'tt_truebend/gl/drawing_helper'

module TT::Plugins::TrueBend
  class BoundingBoxWidget

    include BoundingBoxConstants
    include DrawingHelper
    include InstanceHelper
    include ViewConstants

    # How close to an edge of the bounds the cursor has to be to pick it, in
    # pixels.
    PICK_APERTURE = 10

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Sketchup::Color] color
    # @param [Integer] line_width
    def initialize(instance, color: [255, 128, 0], line_width: 2)
      @instance = instance
      @color = Sketchup::Color.new(*color)
      @line_width = line_width
    end

    # @return [Geom::BoundingBox]
    def bounds
      @instance.bounds
    end

    # @return [Length]
    def width
      (local_bounds.width * scale_x).to_l
    end

    # @return [Length]
    def height
      (local_bounds.height * scale_y).to_l
    end

    # @return [Length]
    def depth
      (local_bounds.depth * scale_z).to_l
    end

    # @return [Length]
    def diagonal
      pts = points
      pts[BB_LEFT_FRONT_BOTTOM].distance(pts[BB_RIGHT_BACK_TOP])
    end

    # @return [Array<Geom::Point3d>]
    def points
      local_bounds.points.map { |point|
        point.transform(@instance.transformation)
      }
    end

    # @param [Integer] index
    # @return [Polygon]
    def polygon(index)
      polygon = local_bounds.polygon(index)
      polygon.transform!(@instance.transformation)
      polygon
    end

    # @return [Array<Polygon>]
    def polygons
      local_bounds.polygons.map { |polygon|
        polygon.transform!(@instance.transformation)
      }
    end

    # @return [Geom::Transformation]
    def scaling_transformation
      Geom::Transformation.scaling(scale_x, scale_y, scale_z)
    end

    # @return [Float]
    def scale_x
      X_AXIS.transform(@instance.transformation).length.to_f
    end

    # @return [Float]
    def scale_y
      Y_AXIS.transform(@instance.transformation).length.to_f
    end

    # @return [Float]
    def scale_z
      Z_AXIS.transform(@instance.transformation).length.to_f
    end

    # @return [Array<Segment>]
    def segments
      local_bounds.segments.map { |polygon|
        polygon.transform!(@instance.transformation)
      }
    end

    # The axis of the instance that the edge of the bounds under the cursor
    # runs along.
    #
    # @param [Integer] x
    # @param [Integer] y
    # @param [Sketchup::View] view
    # @return [Integer, nil] 0, 1 or 2 for the red, green or blue axis.
    def pick_axis(x, y, view)
      pick_helper = view.pick_helper
      picked = axis_segments.select { |_axis, segment|
        pick_helper.pick_segment(segment.points, x, y, PICK_APERTURE)
      }
      # Where edges meet or cross on screen the one nearest the cursor wins.
      cursor = Geom::Point3d.new(x, y, 0)
      nearest = picked.min_by { |_axis, segment|
        screen_distance(view, segment, cursor)
      }
      nearest ? nearest.first : nil
    end

    # @param [Sketchup::View] view
    def draw(view)
      points = lift!(view, segment_points, pixels: 0.2)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = @line_width
      view.drawing_color = @color
      view.draw(GL_LINES, points)
    end

    # Draws the edges of the bounds that run along the given axis of the
    # instance, in the colour of that axis.
    #
    # @param [Sketchup::View] view
    # @param [Integer] axis 0, 1 or 2 for the red, green or blue axis.
    # @param [Integer] line_width
    def draw_axis(view, axis, line_width)
      segments = axis_segments.select { |segment_axis, _segment|
        segment_axis == axis
      }
      points = segments.flat_map { |_axis, segment| segment.points }
      return if points.empty?

      view.line_stipple = STIPPLE_SOLID
      view.line_width = line_width
      set_axis_color(view, axis)
      view.draw(GL_LINES, lift!(view, points, pixels: 0.2))
    end

    private

    # The edges of the bounds, in world coordinates, each with the axis of the
    # instance it runs along. Edges without length are left out.
    #
    # @return [Array<Array(Integer, Segment)>]
    def axis_segments
      segments = local_bounds.segments.map { |segment|
        direction = segment.direction
        next unless direction.valid?

        lengths = direction.to_a.map(&:abs)
        axis = lengths.index(lengths.max)
        [axis, segment.transform!(@instance.transformation)]
      }
      segments.compact
    end

    # How far the cursor is from the line the segment makes on screen.
    #
    # @param [Sketchup::View] view
    # @param [Segment] segment
    # @param [Geom::Point3d] cursor
    # @return [Length]
    def screen_distance(view, segment, cursor)
      point1, point2 = segment.points.map { |point|
        screen_point = view.screen_coords(point)
        screen_point.z = 0
        screen_point
      }
      # A segment seen end on is only a point on screen.
      return cursor.distance(point1) if point1 == point2

      cursor.distance_to_line([point1, point2])
    end

    # @return [Geom::BoundingBox]
    def local_bounds
      extended_bounds = definition(@instance).bounds
      extended_bounds.extend(BoundingBoxHelper)
      extended_bounds
    end

    # @return [Array<Geom::Point3d>]
    def segment_points
      points = local_bounds.segment_points
      points.each { |point| point.transform!(@instance.transformation) }
    end

  end # class
end # module
