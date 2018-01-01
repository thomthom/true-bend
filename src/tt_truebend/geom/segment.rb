module TT::Plugins::TrueBend
  class Segment

    attr_reader :points

    def initialize(point1, point2)
      @points = [point1, point2]
    end

    def length
      @points.first.distance(@points.last)
    end

    def mid_point
      Geom.linear_combination(0.5, @points.first, 0.5, @points.last)
    end

    def transform!(transformation)
      @points.each { |point| point.transform!(transformation) }
      self
    end

  end # class
end # module
