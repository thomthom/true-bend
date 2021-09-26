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

    # @param [Sketchup::ComponentInstance, Sketchup::Group] instance
    # @return [Sketchup::ComponentDefinition]
    def definition(instance)
      if instance.respond_to?(:definition)
        begin
          return instance.definition
        rescue # rubocop:disable Style/RescueStandardError
          # Previously this was the first check, but too many extensions modify
          # Sketchup::Group.definition with a method which is bugged so to avoid
          # all the complaints about extensions not working due to this the call
          # is trapped is a rescue block and any errors will make it fall back
          # to using the old way of finding the group definition.
        end
      end
      if instance.is_a?(Sketchup::Group)
        return instance.entities.parent
      end

      nil # Given entity was not an instance of an definition.
    end

  end
end # module
