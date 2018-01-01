require 'sketchup.rb'

require 'tt_truebend/tools/truebend'
require 'tt_truebend/debug'

module TT::Plugins::TrueBend

  unless file_loaded?(__FILE__)
    menu = UI.menu('Tools')
    menu.add_item('TrueBend') { self.activate_true_bend }
    file_loaded(__FILE__)
  end

  def self.activate_true_bend
    model = Sketchup.active_model
    instances = model.selection.select { |entity|
      entity.is_a?(Sketchup::Group) || entity.is_a?(Sketchup::ComponentInstance)
    }
    unless instances.size == 1
      UI.messagebox('Select a single Group or Component to bend.')
      return
    end
    tool = TrueBendTool.new(instances.first)
    model.select_tool(tool)
  end

end # module
