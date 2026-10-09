local drag = require("drag")
local dictionary = require("__flib__.dictionary")
local format = require("__flib__.format")
local flib_gui = require("__flib__.gui")
local math = require("__flib__.math")
local table = require("__flib__.table")
local flib_technology = require("__flib__.technology")

local auto = require("auto-research")
local constants = require("constants")
local gui_util = require("gui-util")
local research_queue = require("research-queue")
local util = require("util")

--- @class GuiElems
--- @field urq_window LuaGuiElement
--- @field titlebar_flow LuaGuiElement
--- @field search_button LuaGuiElement
--- @field search_textfield LuaGuiElement
--- @field pin_button LuaGuiElement
--- @field close_button LuaGuiElement
--- @field techs_scroll_pane LuaGuiElement
--- @field techs_table LuaGuiElement
--- @field queue_population_label LuaGuiElement
--- @field queue_requeue_multilevel_button LuaGuiElement
--- @field queue_pause_button LuaGuiElement
--- @field queue_trash_button LuaGuiElement
--- @field queue_scroll_pane LuaGuiElement
--- @field queue_table LuaGuiElement
--- @field tech_info_scroll_pane LuaGuiElement
--- @field tech_info_name_label LuaGuiElement
--- @field tech_info_main_slot_frame LuaGuiElement
--- @field tech_info_description_label LuaGuiElement
--- @field tech_info_ingredients_table LuaGuiElement
--- @field tech_info_ingredients_count_label LuaGuiElement
--- @field tech_info_ingredients_time_label LuaGuiElement
--- @field tech_info_effects_table LuaGuiElement
--- @field tech_info_prerequisites_table LuaGuiElement
--- @field tech_info_descendants_table LuaGuiElement
--- @field tech_info_upgrade_group_table LuaGuiElement
--- @field tech_info_footer_frame LuaGuiElement
--- @field tech_info_footer_progressbar LuaGuiElement
--- @field tech_info_footer_pusher LuaGuiElement
--- @field tech_info_footer_cancel_button LuaGuiElement
--- @field tech_info_footer_start_button LuaGuiElement
--- @field tech_info_footer_unresearch_button LuaGuiElement
--- @field welcome_flow LuaGuiElement

--- @class GuiMod
local gui = {}

--- @param self Gui
function gui.cancel_selected_research(self)
  local selected = self.state.selected
  if not selected then
    return
  end
  auto.note_removed(self.force_table, selected.technology, selected.level)
  research_queue.remove(self.force_table.queue, selected.technology, selected.level)
  util.schedule_force_update(self.force)
end

--- @param self Gui
function gui.clear_queue(self)
  local node = self.force_table.queue.head
  while node do
    auto.note_removed(self.force_table, node.technology, node.level)
    node = node.next
  end
  research_queue.clear(self.force_table.queue)
  util.schedule_force_update(self.force)
end

--- @param player_index uint
function gui.destroy(player_index)
  local self = storage.guis[player_index]
  if not self then
    return
  end
  if self.elems.urq_window.valid then
    self.elems.urq_window.destroy()
  end
  storage.guis[player_index] = nil
end

--- @param self Gui
function gui.filter_tech_list(self)
  local query = self.state.search_query
  local dictionaries = dictionary.get_all(self.player.index)
  local technologies = self.force.technologies
  local research_states = self.force_table.research_states
  local show_disabled = self.player.mod_settings["urq-show-disabled-techs"].value --[[@as boolean]]
  local children = self.elems.techs_table.children
  local pack_filter = self.state.pack_filter
  local auto_config = self.force_table.auto
  local producing = pack_filter and auto_config.producing_only and auto.producing(self.force) or nil
  for i = 1, #children do
    local button = children[i]
    local technology_name = button.name
    local technology = technologies[technology_name]
    local research_state = research_states[technology_name]
    -- Show/hide disabled
    local disabled_matched = util.should_show(technology, research_state, show_disabled)
    -- Show/hide upgrade techs
    local upgrade_matched = true
    if technology.upgrade and research_state ~= constants.research_state.conditionally_available then
      upgrade_matched = gui_util.check_upgrade_group(
        technology_name,
        storage.technology_upgrade_groups[flib_technology.get_base_name(technology)],
        research_states
      )
    end
    -- Only techs the allowed science packs can research (auto research panel)
    if pack_filter and disabled_matched then
      for _, ingredient in pairs(technology.research_unit_ingredients) do
        if not auto.pack_allowed(auto_config, producing, ingredient.name) then
          disabled_matched = false
          break
        end
      end
    end
    -- Search query
    local search_matched = #query == 0 -- Automatically pass search on empty query
    if disabled_matched and not search_matched then
      search_matched = gui_util.match_search_strings(technology, query, dictionaries)
    end
    button.visible = disabled_matched and upgrade_matched and search_matched
  end
end

--- @param player_index uint
--- @return Gui?
function gui.get(player_index)
  local self = storage.guis[player_index]
  if not self or not self.elems.urq_window.valid or not self.player.valid then
    if self and self.player.valid then
      self.player.print({ "message.urq-recreated-gui" })
    end
    self = gui.new(game.get_player(player_index) --[[@as LuaPlayer]])
  end
  if self and self.player.force ~= self.force then
    self = gui.new(self.player)
  end
  return self
end

--- @param self Gui
function gui.hide(self)
  if self.state.opening_graph then
    return
  end
  if self.player.opened_gui_type == defines.gui_type.custom and self.player.opened == self.elems.urq_window then
    self.player.opened = nil
  end
  self.elems.urq_window.visible = false
end

--- @param player LuaPlayer
--- @return Gui?
function gui.new(player)
  gui.destroy(player.index)
  if not player.valid then
    return
  end

  --- @type GuiElems
  local elems = flib_gui.add(player.gui.screen, gui.base_template)

  -- Build techs list
  local show_controls = player.mod_settings["urq-show-control-hints"].value --[[@as boolean]]
  local force_table = storage.forces[player.force.index]
  for _, technology in pairs(player.force.technologies) do
    gui_util.technology_slot(
      elems.techs_table,
      technology,
      technology.prototype.level,
      force_table.research_states[technology.name],
      show_controls,
      gui.on_tech_slot_click
    )
  end

  local force = player.force --[[@as LuaForce]]
  --- @class Gui
  local self = {
    elems = elems,
    force = force,
    force_table = force_table,
    player = player,
    state = {
      opening_graph = false,
      pending_update = false,
      pinned = false,
      research_state_counts = {},
      search_open = false,
      search_query = "",
      auto_visible = true,
      pack_filter = false,
      --- @type TechnologyAndLevel?
      selected = nil,
    },
  }
  storage.guis[player.index] = self
  gui_util.toggle_frame_action_button(elems.auto_toggle_button, "flib_settings_white", true)

  gui.update(self)

  return self
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_start_research_click(self, e)
  local selected = self.state.selected
  if not selected then
    return
  end
  gui.start_research(self, selected.technology, selected.level, e.shift, e.control and util.is_cheating(self.player))
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_tech_slot_click(self, e)
  local tags = e.element.tags
  local tech_name, level =
      tags.tech_name, --[[@as string]]
      tags.level --[[@as uint]]
  local technology = self.force.technologies[tech_name]
  if drag.handled(e) then return end  -- (the end of a drag: done by the drop)
  -- Moving within the queue: Ctrl + click picks up, a click on another queued technology drops it there
  local queue = self.force_table.queue
  local held = self.state.held
  if e.element.parent == self.elems.queue_table then
    local key = flib_technology.get_leveled_name(technology, level)
    if e.button == defines.mouse_button_type.left and e.control then
      self.state.held = held ~= key and key or nil
      gui.update_queue(self)
      return
    end
    if held then
      self.state.held = nil
      local node, target = queue.lookup[held], queue.lookup[key]
      if e.button == defines.mouse_button_type.left and node and target and node ~= target then
        node.auto = nil
        research_queue.move(queue, node, target)
      end
      gui.update_queue(self)
      return
    end
  elseif held then
    self.state.held = nil
    gui.update_queue(self)
  end
  if e.button == defines.mouse_button_type.right then
    auto.note_removed(self.force_table, technology, level)
    research_queue.remove(self.force_table.queue, technology, level)
    util.schedule_force_update(self.force)
    return
  end
  if gui_util.is_double_click(e.element) then
    gui.start_research(self, technology, level, e.shift, e.control and util.is_cheating(self.player))
    return
  end
  gui.select_technology(self, technology, level)
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_titlebar_click(self, e)
  if e.button == defines.mouse_button_type.middle then
    self.elems.urq_window.force_auto_center()
  end
end

--- @param self Gui
function gui.on_window_closed(self)
  if self.state.pinned then
    return
  end
  if self.state.search_open then
    gui.toggle_search(self)
    self.player.opened = self.elems.urq_window
    return
  end
  gui.hide(self)
end

--- @param self Gui
function gui.open_in_graph(self)
  self.state.opening_graph = true
  local selected = self.state.selected
  -- Passing `or nil` throws an error
  if selected then
    self.player.open_technology_gui(selected.technology.name)
  else
    self.player.open_technology_gui()
  end
  self.state.opening_graph = false
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.open_in_recipe_book(self, e)
  if not script.active_mods["RecipeBook"] or not e.alt then
    return
  end
  local class, name = string.match(e.element.sprite, "(.*)/(.*)")
  local prototype = nil
  if class == "recipe" then
    prototype = prototypes.recipe[name]
  elseif class == "item" then
    prototype = prototypes.item[name]
  else
    return
  end
  remote.call("RecipeBook", "open_page", self.player.index, prototype)
end

--- @param self Gui
--- @param technology LuaTechnology
--- @param level uint?
function gui.select_technology(self, technology, level)
  if not level then
    level = technology.level
  end
  local former_selected = self.state.selected
  if former_selected and former_selected.technology == technology and former_selected.level == level then
    return
  end
  self.state.selected = { technology = technology, level = level }

  gui.update_queue(self)
  gui.update_tech_list(self)
  gui.update_tech_info(self)
end

--- @param self Gui
--- @param select_tech string?
function gui.show(self, select_tech)
  if self.state.pending_update then
    self.state.pending_update = false
    gui.update(self)
  end
  if select_tech then
    local select_data = self.force.technologies[select_tech]
    gui.select_technology(self, select_data)
  end
  self.elems.urq_window.visible = true
  self.elems.urq_window.bring_to_front()
  if not self.state.pinned then
    self.player.opened = self.elems.urq_window
  end
end

--- @param self Gui
--- @param technology LuaTechnology
--- @param level uint
--- @param to_front boolean?
--- @param instant_research boolean?
function gui.start_research(self, technology, level, to_front, instant_research)
  local push_error
  if instant_research then
    push_error = research_queue.instant_research(self.force_table.queue, technology)
  elseif to_front then
    push_error = research_queue.push_front(self.force_table.queue, technology, level)
  else
    push_error = research_queue.push(self.force_table.queue, technology, level)
  end
  if push_error then
    util.flying_text(self.player, push_error)
    return
  end
  util.schedule_force_update(self.force)
end

--- @param self Gui
function gui.toggle_pinned(self)
  self.state.pinned = not self.state.pinned
  gui_util.toggle_frame_action_button(self.elems.pin_button, "flib_pin_white", self.state.pinned)
  if self.state.pinned then
    self.player.opened = nil
    self.elems.search_button.tooltip = { "gui.search" }
    self.elems.close_button.tooltip = { "gui.close" }
  else
    self.player.opened = self.elems.urq_window
    self.elems.urq_window.force_auto_center()
    self.elems.search_button.tooltip = { "gui.urq-search-instruction" }
    self.elems.close_button.tooltip = { "gui.close-instruction" }
  end
end

--- @param self Gui
function gui.toggle_search(self)
  self.state.search_open = not self.state.search_open
  gui_util.toggle_frame_action_button(self.elems.search_button, "utility/search", self.state.search_open)

  local textfield = self.elems.search_textfield
  textfield.visible = self.state.search_open
  if self.state.search_open then
    textfield.focus()
  else
    self.state.search_query = ""
    textfield.text = ""
    gui.filter_tech_list(self)
  end
end

--- @param self Gui
function gui.toggle_queue_paused(self)
  research_queue.toggle_paused(self.force_table.queue)
  util.schedule_force_update(self.force)
end

--- @param self Gui
function gui.toggle_queue_requeue_multilevel(self)
  research_queue.toggle_requeue_multilevel(self.force_table.queue)
  util.schedule_force_update(self.force)
end

--- @param self Gui
function gui.toggle_visible(self)
  if self.elems.urq_window.visible then
    gui.hide(self)
  else
    gui.show(self)
  end
end

--- @param self Gui
function gui.unresearch(self)
  local selected = self.state.selected
  if not selected then
    return
  end
  research_queue.unresearch(self.force_table.queue, selected.technology)
end

--- @param self Gui
function gui.update(self)
  gui.update_queue(self)
  gui.update_auto(self)
  gui.update_tech_info(self)
  gui.update_tech_list(self)
  gui.filter_tech_list(self)
  gui.update_durations_and_progress(self)
end

--- @param self Gui
function gui.update_durations_and_progress(self)
  local queue_table = self.elems.queue_table
  local techs_table = self.elems.techs_table
  local queue = self.force_table.queue
  local node = queue.head
  while node do
    local technology, level = node.technology, node.level
    local progress = math.floored(flib_technology.get_research_progress(technology, level), 0.01)
    local queue_button = queue_table[flib_technology.get_leveled_name(technology, level)]
    if queue_button then
      queue_button.duration_label.caption = node.duration
      queue_button.progressbar.value = progress
      queue_button.progressbar.visible = progress > 0
    end
    local techs_button = techs_table[technology.name]
    if techs_button then
      techs_button.duration_label.caption = node.duration
      techs_button.progressbar.value = progress
      techs_button.progressbar.visible = progress > 0
    end
    node = node.next
  end
  gui.update_tech_info_footer(self, true)
end

--- @param force LuaForce
function gui.update_force(force)
  for _, player in pairs(force.players) do
    local player_gui = gui.get(player.index)
    if not player_gui then
      goto continue
    end
    if player_gui.elems.urq_window.visible then
      gui.update(player_gui)
    else
      player_gui.state.pending_update = true
    end
    ::continue::
  end
end

--- @param force LuaForce
function gui.update_force_progress(force)
  for _, player in pairs(force.players) do
    local player_gui = gui.get(player.index)
    if player_gui and player_gui.elems.urq_window.visible then
      gui.update_durations_and_progress(player_gui)
    end
  end
end

--- @param self Gui
function gui.update_queue(self)
  local queue = self.force_table.queue

  local requeue_multilevel = queue.requeue_multilevel
  local requeue_multilevel_button = self.elems.queue_requeue_multilevel_button
  if requeue_multilevel then
    requeue_multilevel_button.style = "flib_selected_tool_button"
  else
    requeue_multilevel_button.style = "tool_button"
  end

  local paused = queue.paused
  local pause_button = self.elems.queue_pause_button
  if paused then
    pause_button.style = "flib_selected_tool_button"
    pause_button.tooltip = { "gui.urq-resume-queue" }
  else
    pause_button.style = "tool_button"
    pause_button.tooltip = { "gui.urq-pause-queue" }
  end

  self.elems.queue_trash_button.enabled = queue.len > 0

  local held = self.state.held and queue.lookup[self.state.held]
  if self.state.held and not held then
    self.state.held = nil
  end
  self.elems.queue_population_label.caption = held
      and { "gui.srq-holding", "[technology=" .. held.technology.name .. "]" }
      or { "gui.urq-queue-population", self.force_table.queue.len, constants.queue_limit }

  local selected = self.state.selected or {}
  local research_states = self.force_table.research_states
  local show_controls = self.player.mod_settings["urq-show-control-hints"].value --[[@as boolean]]

  -- Add or update buttons
  local queue_table = self.elems.queue_table
  local i = 0
  local node = queue.head
  while node do
    i = i + 1
    local technology, level = node.technology, node.level
    local name = flib_technology.get_leveled_name(technology, level)
    local button = queue_table[name]
    local is_selected = (selected.technology == technology and selected.level == level) or node == held
    if button then
      gui_util.move_to(button, queue_table, i)
      gui_util.update_technology_slot(
        button,
        technology,
        node.level,
        research_states[technology.name],
        research_queue.contains(queue, technology, level),
        is_selected
      )
    else
      gui_util.technology_slot(
        queue_table,
        technology,
        level,
        research_states[technology.name],
        show_controls,
        gui.on_tech_slot_click,
        is_selected,
        flib_technology.get_leveled_name(technology, level),
        i
      )
    end
    node = node.next
  end
  -- Destroy extra buttons
  local children = queue_table.children
  for i = i + 1, #children do
    children[i].destroy()
  end
  -- (with the fse loader: drag a queued technology onto another to move it there)
  for _, button in pairs(queue_table.children) do
    drag.mark(button, button.name)
  end
end

--- @param self Gui
function gui.update_search_query(self)
  self.state.search_query = self.elems.search_textfield.text

  if game.tick_paused or #self.state.search_query == 0 then
    storage.filter_tech_list[self.player.index] = nil
    gui.filter_tech_list(self)
  else
    storage.filter_tech_list[self.player.index] = game.tick + 30
  end
end

--- @param self Gui
function gui.update_tech_info(self)
  local selected = self.state.selected
  if not selected then
    return
  end
  local technology, level = selected.technology, selected.level

  local show_controls = self.player.mod_settings["urq-show-control-hints"].value --[[@as boolean]]

  -- Flows
  self.elems.welcome_flow.visible = false
  self.elems.tech_info_scroll_pane.visible = true
  self.elems.tech_info_footer_frame.visible = true

  -- Slot
  local main_slot_frame = self.elems.tech_info_main_slot_frame
  main_slot_frame.clear() -- The best thing to do is clear it, otherwise we'd need to diff all the sub-elements
  if technology then
    local button = gui_util.technology_slot(
      main_slot_frame,
      technology,
      level,
      self.force_table.research_states[technology.name],
      show_controls,
      gui.on_tech_slot_click
    )
    button.duration_label.visible = false
    button.progressbar.visible = false
  end

  -- Name and description
  local caption = technology.localised_name
  if flib_technology.is_multilevel(technology) then
    caption = { "", caption, " ", level }
  end
  self.elems.tech_info_name_label.caption = caption
  self.elems.tech_info_description_label.caption = { "?", technology.localised_description, "" }

  -- Ingredients
  local ingredients_table = self.elems.tech_info_ingredients_table
  ingredients_table.clear()
  local ingredients_children = nil
  local researchTrigger = technology.prototype.research_trigger
  if #technology.research_unit_ingredients > 0 then
    ingredients_children = table.map(technology.research_unit_ingredients, function(ingredient)
      return {
        type = "sprite-button",
        style = "transparent_slot",
        sprite = "item/" .. ingredient.name,
        number = ingredient.amount,
        elem_tooltip = { type = "item", name = ingredient.name },
        tooltip = show_controls and script.active_mods["RecipeBook"] and { "gui.urq-tooltip-view-in-recipe-book" },
        handler = { [defines.events.on_gui_click] = gui.open_in_recipe_book },
      }
    end)

    flib_gui.add(ingredients_table, ingredients_children)
    flib_gui.add(ingredients_table, {
      type = "label",
      style = "count_label",
      caption = "[img=quantity-time] " .. format.number(math.round(technology.research_unit_energy / 60, 0.01), true),
    })

    local research_unit_count = flib_technology.get_research_unit_count(technology, level)
    self.elems.tech_info_ingredients_count_label.caption = "[img=quantity-multiplier] "
        .. format.number(research_unit_count, research_unit_count > 9999)
  elseif researchTrigger ~= nil then
    local base = nil
    local name = nil
    local number = 0
    local label = { "technology-trigger." .. researchTrigger.type }
    if researchTrigger.type == "mine-entity" then
      base = "entity"
      name = researchTrigger.entity
    elseif researchTrigger.type == "build-entity" then
      base = "entity"
      name = researchTrigger.entity.name
    elseif researchTrigger.type == "capture-spawner" then
      base = "technology"
      name = technology.name
    elseif researchTrigger.type == "craft-fluid" or researchTrigger.type == "craft-fluids" then
      label = { "technology-trigger.craft-items" }
      base = "fluid"
      name = researchTrigger.fluid
      number = researchTrigger.amount
    elseif researchTrigger.type == "create-space-platform" then
      base = "technology"
      name = technology.name
    elseif researchTrigger.type == "scripted" then
      base = "technology"
      name = technology.name
      label = researchTrigger.trigger_description
    else
      number = researchTrigger.count
      base = "item"
      name = researchTrigger.item.name
    end

    flib_gui.add(ingredients_table, {
      type = "label",
      style = "label",
      caption = label,
    })
    local ingredient = {
      type = "sprite-button",
      style = "transparent_slot",
      sprite = base .. "/" .. name,
      elem_tooltip = { type = base, name = name },
      tooltip = show_controls and script.active_mods["RecipeBook"] and { "gui.urq-tooltip-view-in-recipe-book" },
      handler = { [defines.events.on_gui_click] = gui.open_in_recipe_book },
    }
    if number and number > 0 then ingredient["number"] = number end
    flib_gui.add(ingredients_table, ingredient)
    self.elems.tech_info_ingredients_count_label.caption = ""
  end

  -- Effects
  local effects_table = self.elems.tech_info_effects_table
  effects_table.clear()
  -- patched: effect_button returns nil for some effects (unlock-space-platforms); a nil hole crashed flib_gui.add
  local effect_defs = {}
  for _, effect in pairs(technology.prototype.effects) do
    local template = gui_util.effect_button(effect, show_controls)
    if template ~= nil then
      template.handler = { [defines.events.on_gui_click] = gui.open_in_recipe_book }
      effect_defs[#effect_defs + 1] = template
    end
  end
  flib_gui.add(effects_table, effect_defs)
  effects_table.parent.visible = #effects_table.children > 0

  -- Prerequisites
  local prerequisites = {}
  for _, prerequisite in pairs(technology.prerequisites) do
    prerequisites[#prerequisites + 1] = prerequisite
  end
  gui_util.update_technology_info_sublist(
    self,
    self.elems.tech_info_prerequisites_table,
    gui.on_tech_slot_click,
    prerequisites
  )

  -- Requisites
  local technologies = self.force.technologies
  gui_util.update_technology_info_sublist(
    self,
    self.elems.tech_info_descendants_table,
    gui.on_tech_slot_click,
    table.map(storage.technology_descendants[technology.name] or {}, function(descendant_name)
      return technologies[descendant_name]
    end)
  )

  -- Upgrade group
  local technologies = self.force.technologies
  gui_util.update_technology_info_sublist(
    self,
    self.elems.tech_info_upgrade_group_table,
    gui.on_tech_slot_click,
    table.map(storage.technology_upgrade_groups[flib_technology.get_base_name(technology)] or {}, function(prototype)
      return technologies[prototype.name]
    end)
  )

  -- Footer
  gui.update_tech_info_footer(self)
end

--- @param self Gui
--- @param progress_only boolean?
function gui.update_tech_info_footer(self, progress_only)
  local selected = self.state.selected
  if not selected then
    return
  end
  local technology, level = selected.technology, selected.level
  local research_state = self.force_table.research_states[technology.name]
  local selected_name = flib_technology.get_leveled_name(technology, level)

  local is_disabled = research_state == constants.research_state.disabled
  local is_researched = research_state == constants.research_state.researched
  local is_cheating = util.is_cheating(self.player)

  local elems = self.elems
  local frame = elems.tech_info_footer_frame
  if is_disabled or (is_researched and not is_cheating) then
    frame.visible = false
    return
  else
    frame.visible = true
  end

  local in_queue = research_queue.contains(self.force_table.queue, technology, level)
  local progress = flib_technology.get_research_progress(technology, level)

  local progressbar = elems.tech_info_footer_progressbar
  progressbar.visible = progress > 0
  elems.tech_info_footer_pusher.visible = progress == 0
  if in_queue then
    progressbar.value = progress
    progressbar.caption = {
      "",
      self.force_table.queue.lookup[selected_name].duration,
      " - ",
      { "format-percent", math.round(progress * 100) },
    }
  end

  if not progress_only then
    elems.tech_info_footer_start_button.visible = not is_researched and not in_queue
    elems.tech_info_footer_cancel_button.visible = not is_researched and in_queue
    elems.tech_info_footer_unresearch_button.visible = is_researched and is_cheating
    local config = self.force_table.auto
    local is_goal = auto.index_of(config.goals, technology.name) ~= nil
    local is_blacklisted = auto.index_of(config.blacklist, technology.name) ~= nil
    elems.tech_info_footer_goal_button.visible = not is_researched
    elems.tech_info_footer_goal_button.caption = { is_goal and "gui.srq-remove-goal" or "gui.srq-add-goal" }
    elems.tech_info_footer_blacklist_button.visible = not is_researched
    elems.tech_info_footer_blacklist_button.caption =
      { is_blacklisted and "gui.srq-remove-blacklist" or "gui.srq-add-blacklist" }
  end
end

--- @param self Gui
function gui.update_tech_list(self)
  local techs_table = self.elems.techs_table
  local queue = self.force_table.queue
  local selected = self.state.selected or {}
  local research_states = self.force_table.research_states
  local i = 0
  for _, group in pairs(self.force_table.technology_groups) do
    for j = 1, storage.num_technologies do
      --- @cast j uint
      local technology = group[j]
      if not technology then
        goto continue
      end
      local level = technology.prototype.level
      if flib_technology.is_multilevel(technology) then
        level = math.clamp(
          research_queue.get_highest_level(self.force_table.queue, technology) + 1,
          technology.level,
          technology.prototype.max_level
        ) --[[@as uint]]
      end
      i = i + 1
      local button = techs_table[technology.name] --[[@as LuaGuiElement]]
      if i ~= button.get_index_in_parent() then
        gui_util.move_to(button, techs_table, i)
      end
      gui_util.update_technology_slot(
        button,
        technology,
        level,
        research_states[technology.name],
        research_queue.contains(queue, technology, level),
        selected.technology == technology and selected.level == level
      )
      ::continue::
    end
  end
end

--- @param self Gui
function gui.toggle_auto_panel(self)
  self.state.auto_visible = not self.state.auto_visible
  gui_util.toggle_frame_action_button(self.elems.auto_toggle_button, "flib_settings_white", self.state.auto_visible)
  self.elems.auto_frame.visible = self.state.auto_visible
  if self.state.auto_visible then
    gui.update_auto(self)
  end
end

--- @param self Gui
--- @param e EventData.on_gui_checked_state_changed
function gui.on_auto_checkbox(self, e)
  local key = e.element.tags.key --[[@as string]]
  if key == "pack_filter" then
    self.state.pack_filter = e.element.state
    gui.filter_tech_list(self)
    return
  end
  self.force_table.auto[key] = e.element.state
  auto.changed(self.force_table)
end

--- @param self Gui
--- @param e EventData.on_gui_selection_state_changed
function gui.on_auto_strategy(self, e)
  self.force_table.auto.strategy = auto.strategies[e.element.selected_index] or "balanced"
  auto.changed(self.force_table)
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_auto_pack_click(self, e)
  local pack = e.element.tags.pack --[[@as string]]
  local allowed = self.force_table.auto.allowed
  if e.button == defines.mouse_button_type.right then
    -- only this pack and the ones listed before it
    local before = true
    for _, name in pairs(storage.science_packs) do
      if before then
        allowed[name] = nil
      else
        allowed[name] = false
      end
      if name == pack then
        before = false
      end
    end
  elseif allowed[pack] == false then
    allowed[pack] = nil
  else
    allowed[pack] = false
  end
  auto.changed(self.force_table)
  if self.state.pack_filter then
    gui.filter_tech_list(self)
  end
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_auto_row_select(self, e)
  local technology = self.force.technologies[e.element.tags.tech_name]
  if technology then
    gui.select_technology(self, technology)
  end
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_auto_goal_up(self, e)
  auto.move_goal(self.force_table, e.element.tags.tech_name --[[@as string]], -1)
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_auto_goal_down(self, e)
  auto.move_goal(self.force_table, e.element.tags.tech_name --[[@as string]], 1)
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.on_auto_row_remove(self, e)
  auto.remove(self.force_table, e.element.tags.tech_name --[[@as string]])
end

--- @param self Gui
--- @param e EventData.on_gui_click
function gui.toggle_selected_goal(self, e)
  local selected = self.state.selected
  if not selected then
    return
  end
  local name = selected.technology.name
  if auto.index_of(self.force_table.auto.goals, name) then
    auto.remove(self.force_table, name)
  else
    auto.add(self.force_table, "goals", name, e.shift and 1 or nil)
  end
end

--- @param self Gui
function gui.toggle_selected_blacklist(self)
  local selected = self.state.selected
  if not selected then
    return
  end
  local name = selected.technology.name
  if auto.index_of(self.force_table.auto.blacklist, name) then
    auto.remove(self.force_table, name)
  else
    auto.add(self.force_table, "blacklist", name)
  end
end

--- @param self Gui
--- @param parent LuaGuiElement
--- @param names string[]
--- @param is_goals boolean
local function auto_rows(self, parent, names, is_goals)
  parent.clear()
  local technologies = self.force.technologies
  if #names == 0 then
    parent.add({
      type = "label",
      caption = { is_goals and "gui.srq-no-goals" or "gui.srq-no-blacklist" },
    }).style.font_color = { 0.6, 0.6, 0.6 }
    return
  end
  for i, name in pairs(names) do
    local technology = technologies[name]
    if technology then
      local row = { type = "flow", style_mods = { vertical_align = "center", horizontal_spacing = 4 } }
      row[#row + 1] = {
        type = "sprite-button",
        style = "transparent_slot",
        style_mods = { size = 28 },
        sprite = "technology/" .. name,
        elem_tooltip = { type = "technology", name = name },
        tags = { tech_name = name },
        handler = { [defines.events.on_gui_click] = gui.on_auto_row_select },
      }
      row[#row + 1] = {
        type = "label",
        caption = technology.localised_name,
        style_mods = { horizontally_stretchable = true, horizontally_squashable = true, maximal_width = 200 },
      }
      if is_goals then
        row[#row + 1] = {
          type = "sprite-button",
          style = "mini_button",
          sprite = "utility/hint_arrow_up",
          tooltip = { "gui.srq-move-up" },
          enabled = i > 1,
          tags = { tech_name = name },
          handler = { [defines.events.on_gui_click] = gui.on_auto_goal_up },
        }
        row[#row + 1] = {
          type = "sprite-button",
          style = "mini_button",
          sprite = "utility/hint_arrow_down",
          tooltip = { "gui.srq-move-down" },
          enabled = i < #names,
          tags = { tech_name = name },
          handler = { [defines.events.on_gui_click] = gui.on_auto_goal_down },
        }
      end
      row[#row + 1] = {
        type = "sprite-button",
        style = "mini_tool_button_red",
        sprite = "utility/close",
        tooltip = { "gui.srq-remove" },
        tags = { tech_name = name },
        handler = { [defines.events.on_gui_click] = gui.on_auto_row_remove },
      }
      flib_gui.add(parent, row)
    end
  end
end

--- @param self Gui
function gui.update_auto(self)
  local elems = self.elems
  if not elems.auto_frame.visible then
    return
  end
  local force_table = self.force_table
  local config = force_table.auto

  elems.auto_enabled_checkbox.state = config.enabled
  elems.auto_goals_only_checkbox.state = config.goals_only
  elems.auto_allow_switching_checkbox.state = config.allow_switching
  elems.auto_announce_checkbox.state = config.announce
  elems.auto_deprioritize_infinite_checkbox.state = config.deprioritize_infinite
  elems.auto_producing_only_checkbox.state = config.producing_only
  elems.auto_pack_filter_checkbox.state = self.state.pack_filter
  for i, name in pairs(auto.strategies) do
    if name == config.strategy then
      elems.auto_strategy_dropdown.selected_index = i
    end
  end

  -- Science pack toggles: green = allowed, yellow = allowed but not made lately, red = not allowed
  local producing = config.producing_only and auto.producing(self.force) or nil
  local packs_table = elems.auto_packs_table
  packs_table.clear()
  for _, pack in pairs(storage.science_packs or {}) do
    local style, tooltip = "flib_slot_button_green", "gui.srq-pack-allowed"
    if config.allowed[pack] == false then
      style, tooltip = "flib_slot_button_red", "gui.srq-pack-blocked"
    elseif producing and not producing[pack] then
      style, tooltip = "flib_slot_button_yellow", "gui.srq-pack-not-made"
    end
    flib_gui.add(packs_table, {
      type = "sprite-button",
      style = style,
      sprite = "item/" .. pack,
      tooltip = { "", prototypes.item[pack].localised_name, "\n", { tooltip } },
      tags = { pack = pack },
      handler = { [defines.events.on_gui_click] = gui.on_auto_pack_click },
    })
  end

  -- What auto research does next
  local next_label = elems.auto_next_label
  local queued = research_queue.first_startable(force_table.queue)
  if not config.enabled then
    next_label.caption = { "gui.srq-next-off" }
  elseif queued and not queued.auto then
    next_label.caption = { "gui.srq-next-queue" }
  elseif config.strategy == "random" and not queued then
    next_label.caption = { "gui.srq-next-random" }
  else
    local pick, goal
    if queued and queued.auto then
      pick = queued.technology
    else
      pick, goal = auto.pick(force_table)
    end
    if not pick then
      next_label.caption = { config.goals_only and "gui.srq-next-none-goals" or "gui.srq-next-none" }
    elseif goal and goal ~= pick then
      next_label.caption = { "gui.srq-next-for-goal", "[technology=" .. pick.name .. "]", "[technology=" .. goal.name .. "]" }
    else
      next_label.caption = { "gui.srq-next", "[technology=" .. pick.name .. "]" }
    end
  end

  auto_rows(self, elems.auto_goals_flow, config.goals, true)
  auto_rows(self, elems.auto_blacklist_flow, config.blacklist, false)
end

--- @param caption LocalisedString
local function auto_heading(caption)
  return {
    type = "flow",
    direction = "vertical",
    { type = "line", direction = "horizontal", style_mods = { left_margin = -2, right_margin = -2, top_margin = 4 } },
    { type = "label", style = "heading_2_label", caption = caption },
  }
end

--- @param name string
--- @param key string
--- @param caption string
local function auto_checkbox(name, key, caption)
  return {
    type = "checkbox",
    name = name,
    caption = { "gui." .. caption },
    tooltip = { "gui." .. caption .. "-tooltip" },
    state = false,
    tags = { key = key },
    handler = { [defines.events.on_gui_checked_state_changed] = gui.on_auto_checkbox },
  }
end

gui.base_template = {
  {
    type = "frame",
    name = "urq_window",
    direction = "vertical",
    visible = false,
    elem_mods = { auto_center = true },
    handler = { [defines.events.on_gui_closed] = gui.on_window_closed },
    {
      type = "flow",
      name = "titlebar_flow",
      style = "flib_titlebar_flow",
      drag_target = "urq_window",
      handler = { [defines.events.on_gui_click] = gui.on_titlebar_click },
      {
        type = "label",
        style = "frame_title",
        caption = { "gui-technology-queue.title" },
        ignored_by_interaction = true,
      },
      { type = "empty-widget", style = "flib_titlebar_drag_handle", ignored_by_interaction = true },
      {
        type = "textfield",
        name = "search_textfield",
        style = "urq_search_textfield",
        visible = false,
        clear_and_focus_on_right_click = true,
        handler = { [defines.events.on_gui_text_changed] = gui.update_search_query },
      },
      gui_util.frame_action_button(
        "search_button",
        "utility/search",
        { "gui.urq-search-instruction" },
        gui.toggle_search
      ),
      gui_util.frame_action_button(
        "auto_toggle_button",
        "flib_settings_white",
        { "gui.srq-toggle-auto" },
        gui.toggle_auto_panel
      ),
      gui_util.frame_action_button("pin_button", "flib_pin_white", { "gui.flib-keep-open" }, gui.toggle_pinned),
      gui_util.frame_action_button("close_button", "utility/close", { "gui.close-instruction" }, gui.hide),
    },
    {
      type = "flow",
      style_mods = { horizontal_spacing = 12 },
      {
        type = "flow",
        style_mods = { vertical_spacing = 12, width = 72 * 7 + 12 },
        direction = "vertical",
        {
          type = "frame",
          style = "inside_deep_frame",
          direction = "vertical",
          {
            type = "frame",
            style = "subheader_frame",
            style_mods = { horizontally_stretchable = true },
            { type = "label",        style = "subheader_caption_label", caption = { "gui-technology-queue.title" } },
            { type = "empty-widget", style = "flib_horizontal_pusher" },
            {
              type = "label",
              name = "queue_population_label",
              caption = { "gui.urq-queue-population", 0, constants.queue_limit },
            },
            { type = "line", direction = "vertical" },
            {
              type = "sprite-button",
              name = "queue_requeue_multilevel_button",
              style = "tool_button",
              sprite = "utility/variations_tool_icon",
              tooltip = { "gui.urq-requeue-multilevel-technologies" },
              handler = { [defines.events.on_gui_click] = gui.toggle_queue_requeue_multilevel },
            },
            {
              type = "sprite-button",
              name = "queue_pause_button",
              style = "tool_button",
              sprite = "utility/pause",
              tooltip = { "gui.urq-pause-queue" },
              handler = { [defines.events.on_gui_click] = gui.toggle_queue_paused },
            },
            {
              type = "sprite-button",
              name = "queue_trash_button",
              style = "tool_button_red",
              sprite = "utility/trash",
              tooltip = { "gui.urq-clear-queue" },
              enabled = false,
              handler = { [defines.events.on_gui_click] = gui.clear_queue },
            },
          },
          {
            type = "scroll-pane",
            name = "queue_scroll_pane",
            style = "urq_tech_list_scroll_pane",
            style_mods = { height = 100 * 2, horizontally_stretchable = true },
            vertical_scroll_policy = "auto-and-reserve-space",
            {
              type = "table",
              name = "queue_table",
              style = "slot_table",
              column_count = 7,
            },
          },
        },
        {
          type = "frame",
          style = "inside_shallow_frame",
          direction = "vertical",
          {
            type = "frame",
            style = "subheader_frame",
            style_mods = { horizontally_stretchable = true },
            {
              type = "label",
              name = "tech_info_name_label",
              style = "subheader_caption_label",
              caption = { "gui.urq-no-technology-selected" },
            },
            { type = "empty-widget", style = "flib_horizontal_pusher" },
            {
              type = "sprite-button",
              style = "tool_button",
              sprite = "urq_open_in_graph",
              tooltip = { "gui.urq-open-in-graph" },
              handler = { [defines.events.on_gui_click] = gui.open_in_graph },
            },
          },
          {
            type = "scroll-pane",
            name = "tech_info_scroll_pane",
            style = "flib_naked_scroll_pane",
            style_mods = { horizontally_stretchable = true, vertically_stretchable = true },
            direction = "vertical",
            vertical_scroll_policy = "always",
            visible = false,
            {
              type = "flow",
              style_mods = { horizontal_spacing = 12 },
              {
                type = "frame",
                name = "tech_info_main_slot_frame",
                style = "deep_frame_in_shallow_frame",
              },
              {
                type = "flow",
                direction = "vertical",
                {
                  type = "label",
                  name = "tech_info_description_label",
                  style_mods = { single_line = false, horizontally_stretchable = true },
                  caption = "",
                },
              },
            },
            {
              type = "line",
              direction = "horizontal",
              style_mods = { left_margin = -2, right_margin = -2, top_margin = 4 },
            },
            { type = "label", style = "heading_2_label", caption = { "gui-technology-preview.unit-ingredients" } },
            {
              type = "flow",
              style = "horizontal_flow",
              {
                type = "frame",
                style = "slot_group_frame",
                {
                  type = "table",
                  name = "tech_info_ingredients_table",
                  column_count = 11,
                },
              },
              { type = "label", name = "tech_info_ingredients_count_label", style = "count_label" },
            },
            {
              type = "flow",
              direction = "vertical",
              {
                type = "line",
                direction = "horizontal",
                style_mods = { left_margin = -2, right_margin = -2, top_margin = 4 },
              },
              { type = "label", style = "heading_2_label", caption = { "gui-technology-preview.effects" } },
              {
                type = "table",
                name = "tech_info_effects_table",
                style_mods = { horizontal_spacing = 8 },
                column_count = 12,
              },
            },
            gui_util.tech_info_sublist({ "gui.urq-prerequisites" }, "tech_info_prerequisites_table"),
            gui_util.tech_info_sublist({ "gui.urq-descendants" }, "tech_info_descendants_table"),
            gui_util.tech_info_sublist({ "gui.urq-upgrade-group" }, "tech_info_upgrade_group_table"),
          },
          {
            type = "frame",
            name = "tech_info_footer_frame",
            style = "subfooter_frame",
            visible = false,
            {
              type = "progressbar",
              name = "tech_info_footer_progressbar",
              style = "production_progressbar",
              style_mods = { horizontally_stretchable = true },
              caption = { "format-percent", 0 },
            },
            { type = "empty-widget", name = "tech_info_footer_pusher", style = "flib_horizontal_pusher" },
            {
              type = "button",
              name = "tech_info_footer_goal_button",
              tooltip = { "gui.srq-goal-tooltip" },
              handler = { [defines.events.on_gui_click] = gui.toggle_selected_goal },
            },
            {
              type = "button",
              name = "tech_info_footer_blacklist_button",
              tooltip = { "gui.srq-blacklist-tooltip" },
              handler = { [defines.events.on_gui_click] = gui.toggle_selected_blacklist },
            },
            {
              type = "button",
              name = "tech_info_footer_unresearch_button",
              caption = { "gui-technology-preview.un-research" },
              tooltip = { "gui-technology-preview.un-research-tooltip" },
              visible = false,
              handler = { [defines.events.on_gui_click] = gui.unresearch },
            },
            {
              type = "button",
              name = "tech_info_footer_cancel_button",
              style = "red_button",
              caption = { "gui.urq-cancel-research" },
              tooltip = { "gui.urq-cancel-research" },
              visible = false,
              handler = { [defines.events.on_gui_click] = gui.cancel_selected_research },
            },
            {
              type = "button",
              name = "tech_info_footer_start_button",
              style = "green_button",
              caption = { "gui-technology-preview.start-research" },
              tooltip = { "gui-technology-preview.start-research" },
              handler = { [defines.events.on_gui_click] = gui.on_start_research_click },
            },
          },
          {
            type = "flow",
            name = "welcome_flow",
            style_mods = { padding = 12, vertically_stretchable = true },
            direction = "vertical",
            { type = "label", style_mods = { single_line = false }, caption = { "gui.urq-welcome" } },
          },
        },
      },
      {
        type = "frame",
        style = "inside_deep_frame",
        direction = "vertical",
        {
          type = "frame",
          style = "subheader_frame",
          style_mods = { horizontally_stretchable = true },
          { type = "label", style = "subheader_caption_label", caption = { "gui-technologies-list.title" } },
        },
        {
          type = "scroll-pane",
          name = "techs_scroll_pane",
          style = "urq_tech_list_scroll_pane",
          style_mods = { horizontally_stretchable = true, height = 100 * 7, width = 72 * 8 + 12 },
          vertical_scroll_policy = "auto-and-reserve-space",
          { type = "table", name = "techs_table", style = "slot_table", column_count = 8 },
        },
      },
      {
        type = "frame",
        name = "auto_frame",
        style = "inside_shallow_frame",
        direction = "vertical",
        style_mods = { width = 340, height = 100 * 7 + 36 },
        {
          type = "frame",
          style = "subheader_frame",
          style_mods = { horizontally_stretchable = true },
          { type = "label", style = "subheader_caption_label", caption = { "gui.srq-auto-research" } },
          { type = "empty-widget", style = "flib_horizontal_pusher" },
          auto_checkbox("auto_enabled_checkbox", "enabled", "srq-enabled"),
        },
        {
          type = "scroll-pane",
          style = "flib_naked_scroll_pane",
          style_mods = { horizontally_stretchable = true, vertically_stretchable = true },
          vertical_scroll_policy = "auto",
          horizontal_scroll_policy = "never",
          {
            type = "flow",
            direction = "vertical",
            style_mods = { vertical_spacing = 4, horizontally_stretchable = true },
            { type = "label", name = "auto_next_label", style_mods = { single_line = false, maximal_width = 300 } },
            auto_checkbox("auto_goals_only_checkbox", "goals_only", "srq-goals-only"),
            auto_checkbox("auto_allow_switching_checkbox", "allow_switching", "srq-allow-switching"),
            auto_checkbox("auto_deprioritize_infinite_checkbox", "deprioritize_infinite", "srq-deprioritize-infinite"),
            auto_checkbox("auto_announce_checkbox", "announce", "srq-announce"),
            {
              type = "flow",
              style_mods = { vertical_align = "center", horizontal_spacing = 8 },
              { type = "label", caption = { "gui.srq-strategy" }, tooltip = { "gui.srq-strategy-tooltip" } },
              {
                type = "drop-down",
                name = "auto_strategy_dropdown",
                items = {
                  { "gui.srq-strategy-balanced" },
                  { "gui.srq-strategy-fast" },
                  { "gui.srq-strategy-slow" },
                  { "gui.srq-strategy-cheap" },
                  { "gui.srq-strategy-expensive" },
                  { "gui.srq-strategy-random" },
                },
                selected_index = 1,
                tooltip = { "gui.srq-strategy-tooltip" },
                handler = { [defines.events.on_gui_selection_state_changed] = gui.on_auto_strategy },
              },
            },
            auto_heading({ "gui.srq-packs" }),
            {
              type = "frame",
              style = "slot_group_frame",
              { type = "table", name = "auto_packs_table", style = "slot_table", column_count = 7 },
            },
            auto_checkbox("auto_producing_only_checkbox", "producing_only", "srq-producing-only"),
            auto_checkbox("auto_pack_filter_checkbox", "pack_filter", "srq-pack-filter"),
            auto_heading({ "gui.srq-goals" }),
            { type = "label", caption = { "gui.srq-goals-hint" }, style_mods = { single_line = false, maximal_width = 300 } },
            { type = "flow", name = "auto_goals_flow", direction = "vertical", style_mods = { vertical_spacing = 2 } },
            auto_heading({ "gui.srq-blacklist" }),
            { type = "flow", name = "auto_blacklist_flow", direction = "vertical", style_mods = { vertical_spacing = 2 } },
          },
        },
      },
    },
  },
}

flib_gui.add_handlers(gui, function(e, handler)
  local gui = gui.get(e.player_index)
  if gui then
    handler(gui, e)
  end
end)
gui.dispatch = flib_gui.dispatch
gui.handle_events = flib_gui.handle_events

return gui
