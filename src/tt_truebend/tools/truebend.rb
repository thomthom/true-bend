require 'tt_truebend/constants/boundingbox'
require 'tt_truebend/gl/boundingbox'
require 'tt_truebend/manipulators/drag_handle'
require 'tt_truebend/bender'

module TT::Plugins::TrueBend
  class TrueBendTool

    include BoundingBoxConstants

    def initialize(instance)
      @bend_by_distance = false
      # @bender = Bender.new(instance)
      @boundingbox = BoundingBoxWidget.new(instance)

      segment = @boundingbox.segments.first
      polygon = @boundingbox.polygon(BB_POLYGON_FRONT)

      @bender = Bender.new(instance, segment, polygon.normal)

      @manipulator = DragHandle.new(polygon.center, polygon.normal, color: 'red')

      @manipulator.on_drag {
        @bender.bend(@manipulator.direction)
      }
    end

    def getMenu(menu)
      id = menu.add_item('Segmented') {
        @bender.segmented = !@bender.segmented
      }
      menu.set_validation_proc(id)  {
        @bender.segmented ? MF_CHECKED : MF_ENABLED
      }
    end

    def enableVCB?
      @manipulator.can_adjust?
    end

    def activate
      update_ui
      Sketchup.active_model.active_view.invalidate
    end

    def deactivate(view)
      view.invalidate
    end

    def suspend(view)
      update_ui
      view.invalidate
    end

    def resume(view)
      view.invalidate
    end

    def onReturn(view)
      puts "onReturn"
      return unless @bender.can_bend?
      puts "> bend..."
      model = Sketchup.active_model
      model.start_operation('Bend', true)
      @bender.commit
      model.commit_operation
      model.select_tool(nil) # TODO: Push and pop instead?
    end

    def onCancel(reason, view)
      @bender.reset
      @manipulator.reset
      update_ui
      view.invalidate
    end

    def onUserText(text, view)
      unless text.match(/^[0-9.,;:]+$/)
        # If there are non-numeric characters - check if they have special
        # meaning.
        if text.end_with?('s')
          # Adjust subdivisions.
          @bender.subdivisions = text.to_i
          return
        else
          # Switch adjustment unit.
          @bend_by_distance = !text.end_with?('deg')
        end
      end
      # Adjust the last value.
      # TODO: Make additional check to see if any value can be adjusted.
      #       Don't trust enableVCB? to be fully up to date.
      begin
        if bend_by_distance?
          # TODO: Clean up this.
          d = @bender.direction.clone
          d.length = text.to_l
          @bender.bend(d)
          # @bender.distance = text.to_l
        else
          @bender.angle = text.to_f.degrees
        end
      rescue ArgumentError => error
        # TODO: Don't emit error message directly to user.
        UI.messagebox(error.message)
        return
      end
      @manipulator.distance = @bender.distance
    ensure
      update_ui
      view.invalidate
    end

    def onLButtonDown(flags, x, y, view)
      @manipulator.onLButtonDown(flags, x, y, view)
      view.invalidate
      update_ui
    end

    def onLButtonUp(flags, x, y, view)
      @manipulator.onLButtonUp(flags, x, y, view)
      update_ui
      view.invalidate
    end

    def onMouseMove(flags, x, y, view)
      @manipulator.onMouseMove(flags, x, y, view)
      update_ui
      view.invalidate
    end

    def getExtents
      bounds = Geom::BoundingBox.new
      bounds.add(@bender.bounds)
      bounds.add(@manipulator.bounds)
      # bounds.add(@segmenter.bounds)
      bounds
    end

    def draw(view)
      @bender.draw(view)
      @boundingbox.draw(view)
      @manipulator.draw(view)
      # @segmenter.draw(view)
    end

    private

    def bend_by_distance?
      @bend_by_distance
    end

    def update_ui
      if @manipulator.drag?
        Sketchup.status_text = 'Drag to adjust the amount of bend.'
        # Sketchup.vcb_label = 'Distance'
        # Sketchup.vcb_value = @manipulator.distance
      else
        Sketchup.status_text = 'Pick a handle to start bending the instance.'
        Sketchup.vcb_label = 'Distance'
        # Sketchup.vcb_value = @bender.distance
      end
      if bend_by_distance?
        Sketchup.vcb_label = 'Distance'
        Sketchup.vcb_value = @bender.distance
      else
        Sketchup.vcb_label = 'Angle'
        Sketchup.vcb_value = Sketchup.format_angle(@bender.angle)
      end
      # Sketchup.vcb_label = 'Angle'
      # Sketchup.vcb_value = @bender.angle
    end

  end # class
end # module
