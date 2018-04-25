module TT::Plugins::TrueBend
  module InstanceHelper

    private

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @return [Sketchup::ComponentInstance, Sketchup::Group]
    def ensure_groups_are_uniqe(instance)
      if instance.is_a?(Sketchup::Group)
        instance.make_unique
      else
        instance
      end
    end

    # @param [Sketchup::ComponentInstance, Sketchup::Group] entity
    def instance?(entity)
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    end

  end
end # module
