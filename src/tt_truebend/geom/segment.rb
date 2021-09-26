module TT::Plugins::TrueBend
  class Segment

    attr_reader :points

    # @param [Geom::Point3d] point1
    # @param [Geom::Point3d] point2
    def initialize(point1, point2)
      @points = [point1.clone, point2.clone]
    end

    # @return [Geom::Point3d]
    def start
      @points.first
    end

    # @return [Geom::Point3d]
    def end
      @points.last
    end

    # @param [Array(Geom::Point3d, Geom::Vector3d)] plane
    # @return [Geom::Point3d]
    def intersect_plane(plane)
      # http://sketchup.thomthom.net/extensions/TT_TrueBend/reports/report/25887?version=1.0.1
      return nil unless line[1].valid?

      point = Geom.intersect_line_plane(line, plane)
      return nil if point.nil?

      v1 = point.vector_to(@points[0])
      v2 = point.vector_to(@points[1])
      return nil unless v1.valid? && v2.valid?
      return nil if v1.samedirection?(v2)

      point
    end

    # @return [Length]
    def length
      @points.first.distance(@points.last)
    end

    # @return [Geom::Vector3d]
    def direction
      @points.first.vector_to(@points.last)
    end

    # @return [Array(Geom::Point3d, Geom::Vector3d)]
    def line
      [@points[0], @points[0].vector_to(@points[1])]
    end

    # @return [Geom::Point3d]
    def mid_point
      Geom.linear_combination(0.5, @points.first, 0.5, @points.last)
    end

    # @param [Array(Geom::Point3d, Geom::Vector3d)] plane
    # @return [Array(Segment, Segment)]
    def split(plane)
      point = intersect_plane(plane)
      return [self] if point.nil?

      [self.class.new(@points[0], point), self.class.new(point, @points[1])]
    end

    # @param [Geom::Transformation] transformation
    # @return [Segment]
    def transform(transformation)
      pt1, pt2 = @points.map { |point| point.transform(transformation) }
      self.class.new(pt1, pt2)
    end

    # @param [Geom::Transformation] transformation
    # @return [Segment]
    def transform!(transformation)
      @points.each { |point| point.transform!(transformation) }
      self
    end

    # @return [Geom::Transformation]
    def transformation
      origin = @points.first
      x_axis = direction
      y_axis = x_axis.axes.x
      z_axis = x_axis.axes.y
      Geom::Transformation.axes(origin, x_axis, y_axis, z_axis)
    end

  end # class
end # module
