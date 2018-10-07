require 'delegate.rb'

require 'tt_truebend/dpi/pick_helper'
require 'tt_truebend/dpi/view'
require 'tt_truebend/dpi'

module TT::Plugins::TrueBend
# Shim that takes care of dealing monitor DPI.
#
# The users of this class work with logical units and they are automatically
# converted to device pixels for the API to consume where appropriate.
#
# @note Not possible to make this a mix-in module because Sketchup::InputPoint
#   check the type by strict checks instead of an is_a? check.
class HighDpiInputPoint < SimpleDelegator

  # @overload initialize
  #
  # @overload initialize(inputpoint)
  #   @param [Sketchup::InputPoint, HighDpiInputPoint] inputpoint
  def initialize(*args)
    ip = if args.empty?
      Sketchup::InputPoint.new
    elsif args.first.is_a?(Sketchup::InputPoint)
      args.first
    else
      Sketchup::InputPoint.new(*args)
    end
    super(ip)
  end

  # @param [HighDpiInputPoint] ip
  # @return [HighDpiInputPoint]
  def copy!(ip)
    __getobj__.copy!(ip.__getobj__)
    self
  end

  # @param [Sketchup::View, HighDpiView]
  def draw(view)
    view = view.view if view.is_a?(HighDpiView)
    __getobj__.draw(view)
  end

  # @overload pick(view, x, y, inputpoint = nil)
  #   @param [Sketchup::View, HighDpiView] view
  #   @param [Integer] x
  #   @param [Integer] y
  #   @param [Integer] inputpoint
  #
  # @return [Boolean]
  def pick(*args)
    args[0] = args[0].view if args[0].is_a?(HighDpiView)
    args[1] *= DPI.scale_factor # x
    args[2] *= DPI.scale_factor # y
    args[3] = args[3].__getobj__ if args.size >= 3 && args[3].is_a?(self.class)
    __getobj__.pick(*args)
  end

end # class
end # module
