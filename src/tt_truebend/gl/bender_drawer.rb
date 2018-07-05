require 'tt_truebend/constants/view'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/gl/drawing_helper'
require 'tt_truebend/gl/grid'
require 'tt_truebend/gl/slicer'
require 'tt_truebend/gl/subdivided_segment'
require 'tt_truebend/helpers/edge'
require 'tt_truebend/helpers/instance'
require 'tt_truebend/geom/polar_projection'
require 'tt_truebend/geom/segment'
require 'tt_truebend/app_settings'

module TT::Plugins::TrueBend
  module BenderDrawer

    include DrawingHelper
    include ViewConstants

    TEXT_OPTIONS = {
      font: 'Arial',
      size: 10,
      bold: true,
      color: 'purple'
    }.freeze

    private

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] points
    # @param [Float] line_width
    def draw_projected_reference_segment(view, points, line_width)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = line_width
      view.drawing_color = 'red'
      view.draw(GL_LINE_STRIP, points)
      view.draw_points(points, 6, DRAW_FILLED_SQUARE, 'red')
    end

    # @param [Sketchup::View] view
    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [PolarProjection] projection
    # @param [Segmenter] segmenter
    # @param [Boolean] is_convex
    def draw_projected_grid(view, instance, projection, segmenter, is_convex)
      bounds = BoundingBoxWidget.new(instance)
      grid = Grid.new(bounds.width, bounds.height)
      grid.x_subdivs = segmenter.subdivisions
      arc_grid = projection.project(grid.segment_points, is_convex)
      view.line_stipple = STIPPLE_LONG_DASH
      view.line_width = 1
      view.drawing_color = 'red'
      view.draw(GL_LINES, lift(view, arc_grid))
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] points
    # @param [Sketchup::Color] color
    def draw_mesh(view, points, color)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = 2
      view.drawing_color = color
      view.draw(GL_LINES, points)
      view.draw_points(points, 4, DRAW_FILLED_SQUARE, color)
    end

    # @param [Sketchup::View] view
    # @param [Geom::Point3d] point1
    # @param [Geom::Point3d] point2
    def draw_radius_segment(view, point1, point2)
      view.line_stipple = STIPPLE_SOLID
      view.line_width = 1
      view.draw_points([point1, point2], 6, DRAW_CROSS, 'purple')

      view.line_stipple = STIPPLE_SHORT_DASH
      view.drawing_color = 'purple'
      view.draw(GL_LINES, [point1, point2])
    end

    # @param [Sketchup::View] view
    # @param [Array(Geom::Point3d, Geom::Point3d)] radius_segment (Origin, PointOnCurve)
    # @param [Array<Geom::Point3d>] bend_curve
    # @param [Length] sagitta
    def draw_sagitta(view, radius_segment, bend_curve, sagitta)
      origin, point_on_bend = radius_segment
      direction = point_on_bend.vector_to(origin)
      return unless direction.valid?
      # Sagitta line:
      view.line_stipple = STIPPLE_DOTTED
      view.drawing_color = 'purple'
      view.draw(GL_LINES, bend_curve.first, bend_curve.last)
      # Sagitta point:
      sagitta_point = point_on_bend.offset(direction, sagitta)
      view.line_stipple = ''
      view.draw_points([sagitta_point], 6, DRAW_CROSS, 'purple')
    end

    # @param [Sketchup::View] view
    # @param [Geom::Point3d] origin
    # @param [Geom::Point3d] point1
    # @param [Geom::Point3d] point2
    def draw_pie_sides(view, origin, point1, point2)
      view.drawing_color = 'purple'
      view.line_stipple = STIPPLE_LONG_DASH
      view.line_width = 2
      view.draw(GL_LINES, [origin, point1])
      view.line_width = 1
      view.draw(GL_LINES, [origin, point2])
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] polar_points
    # @param [Float] degrees
    def draw_bend_angle(view, polar_points, degrees)
      v1 = origin.vector_to(polar_points.first)
      v2 = origin.vector_to(polar_points.last)
      full_angle = full_angle_between(v1, v2)
      formatted_angle = Sketchup.format_angle(full_angle)
      screen_origin = view.screen_coords(origin)
      text = "#{formatted_angle}°"
      text << " (#{degrees}°)" if SETTINGS.debug_draw_debug_info?
      view.draw_text(screen_origin, text, TEXT_OPTIONS)
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] polar_points
    # @param [Array(Geom::Point3d, Geom::Point3d)] radius_segment
    # @param [Float] degrees
    def draw_bend_info(view, polar_points, radius_segment, degrees)
      draw_pie_sides(view, radius_segment.first, polar_points.first, polar_points.last)
      draw_radius_segment(view, radius_segment.last, radius_segment.first)
      draw_bend_angle(view, polar_points, degrees)
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] polar_points
    # @param [Length] length  Length of `polar_points`
    def draw_debug_bend_info(view, polar_points, length, arc_length, segment)
      return unless SETTINGS.debug_draw_debug_info?
      options = TEXT_OPTIONS.dup

      # Curve Length
      pt = view.screen_coords(polar_points.first)
      options[:color] = 'red'
      view.draw_text(pt, "#{length} (#{arc_length})", options)

      # Segment Length
      pt = view.screen_coords(segment.points.last)
      options[:color] = 'green'
      view.draw_text(pt, segment.length.to_s, options)
    end

    # @param [Sketchup::View] view
    # @param [Array<Array(Geom::Point3d, Geom::Vector3d)>] planes
    # @param [Geom::Transformation] tr_to_segment_space
    def draw_debug_planes(view, planes, tr_to_segment_space)
      return unless SETTINGS.debug_draw_slice_planes?
      planes.each { |plane|
        local_plane = plane.map { |n| n.transform(tr_to_segment_space) }
        draw_plane(view, local_plane, 1.m, 'red')
      }
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] mesh_points
    def draw_debug_global_mesh(view, mesh_points)
      return unless SETTINGS.debug_draw_global_mesh?
      draw_mesh(view, mesh_points, 'orange')
    end

    # @param [Sketchup::View] view
    # @param [Array<Geom::Point3d>] mesh_points
    # @param [Geom::Transformation] to_local
    def draw_debug_local_mesh(view, mesh_points, to_local)
      return unless SETTINGS.debug_draw_local_mesh?
      local_mesh = mesh_points.map { |pt| pt.transform(to_local) }
      draw_mesh(view, local_mesh, 'purple')
    end

  end # module
end # module
