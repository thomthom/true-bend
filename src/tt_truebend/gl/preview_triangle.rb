module TT::Plugins::TrueBend
  # A vertex of a {PreviewTriangle}. The coordinates are plain Floats, because
  # reading a coordinate from a `Geom::Point3d` is slow, and the triangles are
  # sliced and projected on every redraw.
  class PreviewVertex

    # @return [Float] In inches.
    attr_reader :x, :y, :z

    # The components of the vertex normal that the triangle is shaded by.
    #
    # @return [Float]
    attr_reader :normal_x, :normal_y, :normal_z

    # @param [Geom::Point3d] position
    # @param [Geom::Vector3d] normal
    # @return [PreviewVertex] A vertex that returns these two objects from
    #   {#position} and {#normal}.
    def self.from_geom(position, normal)
      x, y, z = position.to_a
      normal_x, normal_y, normal_z = normal.to_a
      new(x.to_f, y.to_f, z.to_f, normal_x, normal_y, normal_z, position, normal)
    end

    # @param [Float] x
    # @param [Float] y
    # @param [Float] z
    # @param [Float] normal_x
    # @param [Float] normal_y
    # @param [Float] normal_z
    # @param [Geom::Point3d, nil] position The position as an object, if the
    #   caller has it.
    # @param [Geom::Vector3d, nil] normal The normal as an object, if the
    #   caller has it.
    def initialize(x, y, z, normal_x, normal_y, normal_z, position = nil, normal = nil)
      @x = x
      @y = y
      @z = z
      @normal_x = normal_x
      @normal_y = normal_y
      @normal_z = normal_z
      @position = position
      @normal = normal
    end

    # The same object is returned every time, because a vertex is drawn once
    # for each triangle that shares it.
    #
    # @return [Geom::Point3d]
    def position
      @position ||= Geom::Point3d.new(@x, @y, @z)
    end

    # @return [Geom::Vector3d] The same object every time, like {#position}.
    def normal
      @normal ||= Geom::Vector3d.new(@normal_x, @normal_y, @normal_z)
    end

    # @param [PreviewVertex] other
    # @param [Float] ratio
    # @return [PreviewVertex] The vertex that is the given ratio of the way
    #   from this vertex to the other one.
    def interpolate(other, ratio)
      x = @x + ((other.x - @x) * ratio)
      y = @y + ((other.y - @y) * ratio)
      z = @z + ((other.z - @z) * ratio)
      normal_x = @normal_x + ((other.normal_x - @normal_x) * ratio)
      normal_y = @normal_y + ((other.normal_y - @normal_y) * ratio)
      normal_z = @normal_z + ((other.normal_z - @normal_z) * ratio)
      PreviewVertex.new(x, y, z, normal_x, normal_y, normal_z)
    end

  end # class

  # A triangle of a face in the preview of the bend.
  class PreviewTriangle

    # @return [Array(PreviewVertex, PreviewVertex, PreviewVertex)]
    attr_reader :vertices

    # @return [Sketchup::Color]
    attr_reader :front_color, :back_color

    # @param [Array(PreviewVertex, PreviewVertex, PreviewVertex)] vertices
    # @param [Sketchup::Color] front_color
    # @param [Sketchup::Color] back_color
    def initialize(vertices, front_color, back_color)
      @vertices = vertices
      @front_color = front_color
      @back_color = back_color
    end

    # @return [Array(Geom::Point3d, Geom::Point3d, Geom::Point3d)]
    def positions
      @vertices.map(&:position)
    end

    # @return [Array(Geom::Vector3d, Geom::Vector3d, Geom::Vector3d)]
    def normals
      @vertices.map(&:normal)
    end

    # @return [Geom::Vector3d] A vector perpendicular to the triangle, on the
    #   side the vertices are counter-clockwise from. It is not valid if the
    #   triangle has no area.
    def face_normal
      a, b, c = positions
      (b - a) * (c - a)
    end

  end # class
end # module
