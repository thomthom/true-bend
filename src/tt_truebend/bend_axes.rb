require 'tt_truebend/geom/segment'
require 'tt_truebend/helpers/instance'

module TT::Plugins::TrueBend
  # Describes a bend of an instance in terms of the instance's own axes; which
  # axis the bend runs along and which face of its bounds it bends towards.
  class BendAxes

    include InstanceHelper

    # Indices of the instance axes.
    X = 0
    Y = 1
    Z = 2

    AXES = [X_AXIS, Y_AXIS, Z_AXIS].freeze

    # Faces of the instance bounds, as the axis they face along and which end
    # of that axis they are on.
    FRONT = [Y, -1].freeze
    RIGHT = [X, 1].freeze
    TOP = [Z, 1].freeze

    # The faces an instance can bend towards, for each axis the bend can run
    # along. The first one is the default.
    FACES = [
      [FRONT, TOP],   # Along X
      [RIGHT, TOP],   # Along Y
      [FRONT, RIGHT], # Along Z
    ].freeze

    # The ways an instance can be bent along the given axis, default first.
    #
    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Integer] axis `X`, `Y` or `Z`
    # @return [Array<BendAxes>]
    def self.along(instance, axis)
      FACES[axis].map { |face| new(instance, axis, face) }
    end

    # @return [Integer] `X`, `Y` or `Z`
    attr_reader :axis

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @param [Integer] axis `X`, `Y` or `Z`
    # @param [Array(Integer, Integer)] face `FRONT`, `RIGHT` or `TOP`
    def initialize(instance, axis, face)
      @instance = instance
      @axis = axis
      @face = face
    end

    # The instance cannot be bent along an axis it has no extent in.
    def can_bend?
      segment.direction.valid? && normal.valid?
    end

    # The reference segment for the bend, in world coordinates. It runs along
    # the axis, through the origin of the instance, for the extent of its
    # bounds.
    #
    # @return [Segment]
    def segment
      bounds = local_bounds
      Segment.new(point_on_axis(bounds.min), point_on_axis(bounds.max))
    end

    # The direction the instance bends towards, in world coordinates. This is
    # the outward direction of the face.
    #
    # @return [Geom::Vector3d]
    def normal
      face_axis, side = @face
      axes = AXES.map { |axis| axis.transform(@instance.transformation) }
      outward = axes.delete_at(face_axis)
      normal = axes[0] * axes[1]
      return normal unless normal.valid?

      normal.reverse! if (normal % outward) * side < 0
      normal.normalize
    end

    # The center of the face the instance bends towards, in world coordinates.
    #
    # @return [Geom::Point3d]
    def face_center
      face_axis, side = @face
      corner = side < 0 ? local_bounds.min : local_bounds.max
      coordinates = local_bounds.center.to_a
      coordinates[face_axis] = corner[face_axis]
      Geom::Point3d.new(coordinates).transform(@instance.transformation)
    end

    private

    # The point on the axis that is level with the given point, in world
    # coordinates.
    #
    # @param [Geom::Point3d] point In instance coordinates.
    # @return [Geom::Point3d]
    def point_on_axis(point)
      coordinates = [0, 0, 0]
      coordinates[@axis] = point[@axis]
      Geom::Point3d.new(coordinates).transform(@instance.transformation)
    end

    # @return [Geom::BoundingBox]
    def local_bounds
      definition(@instance).bounds
    end

  end # class
end # module
