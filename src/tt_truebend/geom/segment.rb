module TT::Plugins::TrueBend
  class Segment

    attr_reader :points

    def initialize(point1, point2)
      @points = [point1, point2]
    end

    def start
      @points[0]
    end

    def end
      @points[1]
    end

    def intersect_plane(plane)
      point = Geom.intersect_line_plane(line, plane)
      return nil if point.nil?
      v1 = point.vector_to(@points[0])
      v2 = point.vector_to(@points[1])
      return nil unless v1.valid? && v2.valid?
      return nil if v1.samedirection?(v2)
      point
    end

    def length
      @points.first.distance(@points.last)
    end

    def line
      [@points[0], @points[0].vector_to(@points[1])]
    end

    def mid_point
      Geom.linear_combination(0.5, @points.first, 0.5, @points.last)
    end

    def split(plane)
      point = intersect_plane(plane)
      return [self] if point.nil?
      [Segment.new(@points[0], point), Segment.new(point, @points[1])]
    end

    def transform!(transformation)
      @points.each { |point| point.transform!(transformation) }
      self
    end

  end # class
end # module
