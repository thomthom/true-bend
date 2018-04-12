module TT::Plugins::TrueBend
  module DrawingHelper

    def lift(view, points, pixels: 1)
      lift!(view, points.map(&:clone), pixels: pixels)
    end

    def lift!(view, points, pixels: 1)
      direction = view.camera.direction.reverse
      points.each { |point|
        # Take one pixel and multiply with the pixel value to allow for
        # fractional offset.
        distance = view.pixels_to_model(1, point) * pixels
        point.offset!(direction, distance)
      }
    end

  end
end # module
