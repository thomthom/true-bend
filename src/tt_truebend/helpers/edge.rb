require 'tt_truebend/helpers/instance'

module TT::Plugins::TrueBend
  module EdgeHelper

    include InstanceHelper

    private

    def detect_new_edges(entities)
      raise ArgumentError, 'expected block' unless block_given?
      existing_edges = entities.grep(Sketchup::Edge)
      yield
      edges = entities.grep(Sketchup::Edge)
      edges - existing_edges
    end

    # @param [Sketchup::Entities] entities
    def explode_curves(entities)
      entities.each { |entity|
        if entity.is_a?(Sketchup::Edge)
          entity.explode_curve
        elsif instance?(entity)
          entity.make_unique
          explode_curves(definition(entity).entities)
        end
      }
      nil
    end

    def smooth_new_edges(entities, &block)
      new_edges = detect_new_edges(entities, &block)
      new_edges.each { |edge|
        edge.soft = true
        edge.smooth = true
        edge.casts_shadows = false
      }
      new_edges
    end

  end
end # module
