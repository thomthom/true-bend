require 'sketchup.rb'

require 'tt_truebend/helpers/instance'
require 'tt_truebend/tools/truebend'
require 'tt_truebend/debug'

module TT::Plugins::TrueBend

  unless file_loaded?(__FILE__)
    menu = UI.menu('Tools')
    menu.add_item('TrueBend') { activate_true_bend }
    UI.add_context_menu_handler do |context_menu|
      selection = Sketchup.active_model.selection
      if selection.size == 1 && instance?(selection[0])
        context_menu.add_item('TrueBend') { activate_true_bend }
      end
    end
    file_loaded(__FILE__)
  end

  extend InstanceHelper

  def self.activate_true_bend
    model = Sketchup.active_model
    instances = model.selection.select { |entity| instance?(entity) }
    unless instances.size == 1
      UI.messagebox('Select a single Group or Component to bend.')
      return
    end
    tool = TrueBendTool.new(instances.first)
    model.tools.push_tool(tool)
  end

end # module
