require 'delegate.rb'

require 'tt_truebend/dpi/view'
require 'tt_truebend/dpi'

module TT::Plugins::TrueBend
# Shim that takes care of dealing monitor DPI.
#
# The users of this class work with logical units and they are automatically
# converted to device pixels for the API to consume where appropriate.
class HighDpiPickHelper < SimpleDelegator

  # @param [Sketchup::PickHelper] pick_helper
  def initialize(pick_helper)
    unless pick_helper.is_a?(Sketchup::PickHelper)
      raise TypeError, "Expected Sketchup::PickHelper, got #{pick_helper.class.name}"
    end

    super(pick_helper)
  end

  # @param [Integer] x
  # @param [Integer] y
  # @param [Integer] aperture
  # @return [Integer] Number of entities picked
  def do_pick(x, y, aperture = 0)
    super(DPI.to_device(x), DPI.to_device(y), DPI.to_device(aperture))
  end

  # @param [Integer] x
  # @param [Integer] y
  # @param [Integer] aperture
  # @return [HighDpiPickHelper]
  def init(x, y, aperture = 0)
    super(DPI.to_device(x), DPI.to_device(y), DPI.to_device(aperture))
    self
  end

  # @overload pick_segment(points, x, y, aperture = 0)
  #   @param [Array<Geom::Point3d>] points
  #   @param [Integer] x
  #   @param [Integer] y
  #   @param [Integer] aperture
  #
  # @overload pick_segment(x, y, aperture = 0)
  #   @param [Integer] x
  #   @param [Integer] y
  #   @param [Integer] aperture
  #
  # @return [Integer, false] an index of the point in the array if you clicked
  #   on a point or a negative index of a segment if you clicked on a segment
  def pick_segment(*args)
    if args.first.is_a?(Array)
      args[1] *= DPI.scale_factor # x
      args[2] *= DPI.scale_factor # y
      args[3] *= DPI.scale_factor if args.size >= 4 # aperture
    else
      args[0] *= DPI.scale_factor # x
      args[1] *= DPI.scale_factor # y
      args[3] *= DPI.scale_factor if args.size >= 3 # aperture
    end
    super(*args)
  end

  # @overload test_point(point, x, y, aperture = 0)
  #   @param [Array<Geom::Point3d>] point
  #   @param [Integer] x
  #   @param [Integer] y
  #   @param [Integer] aperture
  #
  # @overload test_point(x, y, aperture = 0)
  #   @param [Integer] x
  #   @param [Integer] y
  #   @param [Integer] aperture
  #
  # @return [Boolean]
  def test_point(*args)
    args[1] *= DPI.scale_factor if args.size >= 2 # x
    args[2] *= DPI.scale_factor if args.size >= 3 # y
    args[3] *= DPI.scale_factor if args.size >= 4 # aperture
    super(*args)
  end

  # @return [HighDpiView]
  def view
    HighDpiView.new(super)
  end

end # class
end # module
