module TT::Plugins::TrueBend
  module EdgeHelper

    def detect_new_edges(entities)
      raise ArgumentError, 'expected block' unless block_given?
      existing_edges = entities.grep(Sketchup::Edge)
      yield
      edges = entities.grep(Sketchup::Edge)
      edges - existing_edges
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
