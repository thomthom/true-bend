require 'sketchup'

require 'tt_truebend/helpers/instance'
require 'tt_truebend/tools/truebend'
require 'tt_truebend/app_settings'
require 'tt_truebend/command'
require 'tt_truebend/debug'

module TT::Plugins::TrueBend

  PATH_IMAGES = File.join(PATH, 'images')

  unless file_loaded?(__FILE__)
    cmd = UICommand.new('TrueBend') { activate_true_bend }
    cmd.tooltip = 'TrueBend'
    cmd.status_bar_text = 'Bend geometry to a given radius or angle.'
    cmd.icon = File.join(PATH_IMAGES, 'bend.png')
    cmd_activate_true_bend = cmd

    menu = UI.menu('Tools')
    menu.add_item(cmd_activate_true_bend)

    toolbar = UI::Toolbar.new(EXTENSION[:name])
    toolbar.add_item(cmd_activate_true_bend)
    toolbar.restore

    UI.add_context_menu_handler do |context_menu|
      selection = Sketchup.active_model.selection
      if selection.size == 1 && instance?(selection[0])
        context_menu.add_item(cmd_activate_true_bend)
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
    begin
      tool = TrueBendTool.new(instances.first)
      model.tools.push_tool(tool)
    rescue TrueBendTool::BendError
      message = 'Unable to bend because the distance along the x-axis is zero.'
      UI.messagebox(message)
    end
  end

end # module
