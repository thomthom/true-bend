module TT::Plugins::TrueBend
  class Polygon

    attr_reader :points

    def initialize(*args)
      if args.size == 1 && args.first.is_a?(Array)
        @points = args.first
      elsif args.size >= 3
        @points = args
      else
        raise ArgumentError,
            "polygons require at least 3 points (#{@points.size} given)"
      end
    end

    def center
      total = @points.inject(ORIGIN) { |memo, point| memo + point.to_a }
      total.x /= @points.size
      total.y /= @points.size
      total.z /= @points.size
      total
    end

    def normal
      # Naive computation - just picks a triangular set and uses that for the
      # computation.
      # TODO: Take into account that segments might be colinear.
      # https://www.khronos.org/opengl/wiki/Calculating_a_Surface_Normal
      u = @points[1].vector_to(@points[0])
      v = @points[2].vector_to(@points[0])
      normal = u * v
      normal.normalize!
      normal
    end

    def transform!(transformation)
      @points.each { |point| point.transform!(transformation) }
      self
    end

  end # class
end # module
