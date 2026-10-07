local dictionary = require("__flib__.dictionary")
local flib_technology = require("__flib__.technology")

local auto = require("auto-research")
local gui = require("gui")
local migrations = require("migrations")
local research_queue = require("research-queue")
local drag_hook = require("drag")
local util = require("util")

-- Bootstrap

script.on_init(function()
  --- @type table<uint, integer>
  storage.filter_tech_list = {}
  --- @type table<uint, ForceTable>
  storage.forces = {}
  --- @type table<uint, Gui?>
  storage.guis = {}
  --- @type table<uint, boolean>
  storage.update_force_guis = {}

  -- game.forces is apparently keyed by name, not index
  for _, force in pairs(game.forces) do
    migrations.init_force(force)
  end
  migrations.generic()

  -- Add each force's current research to the queue
  for _, force in pairs(game.forces) do
    local current_research = force.current_research
    if current_research then
      research_queue.push(storage.forces[force.index].queue, current_research, current_research.level)
      gui.update_force(force)
    end
    util.schedule_force_update(force)
  end
  for _, player in pairs(game.players) do
    migrations.apply_default_lists(player)
  end
end)

script.on_configuration_changed(function(data)
  -- Recreate the cache
  migrations.generic()
end)

-- Dictionaries

dictionary.handle_events()

-- Force and Player

script.on_event(defines.events.on_force_created, function(e)
  migrations.init_force(e.force)
  migrations.migrate_force(e.force)
end)

script.on_event(defines.events.on_player_created, function(e)
  local player = game.get_player(e.player_index)
  if not player then
    return
  end
  migrations.migrate_player(player)
  migrations.apply_default_lists(player)
end)

script.on_event({
  defines.events.on_player_toggled_map_editor,
  defines.events.on_player_cheat_mode_enabled,
  defines.events.on_player_cheat_mode_disabled,
}, function(e)
  local player_gui = gui.get(e.player_index)
  if player_gui then
    gui.update_tech_info_footer(player_gui)
  end
end)

script.on_event(defines.events.on_player_changed_surface, function(e)
  -- Recreate GUI if the force changed
  gui.get(e.player_index)
end)

-- Gui

gui.handle_events()

script.on_event(defines.events.on_gui_opened, function(e)
  local player = game.get_player(e.player_index)
  if not player or player.opened_gui_type ~= defines.gui_type.research then
    return
  end
  local player_gui = gui.get(e.player_index)
  if player_gui and not player_gui.state.opening_graph then
    local opened = player.opened --[[@as LuaTechnology?]]
    player.opened = nil
    gui.show(player_gui, opened and opened.name or nil)
  end
end)

script.on_event(defines.events.on_gui_closed, function(e)
  if gui.dispatch(e) or e.gui_type ~= defines.gui_type.research then
    return
  end
  local player_gui = gui.get(e.player_index)
  if player_gui and player_gui.elems.urq_window.visible and not player_gui.state.pinned then
    player_gui.player.opened = player_gui.elems.urq_window
  end
end)

script.on_event("urq-focus-search", function(e)
  local player_gui = gui.get(e.player_index)
  if not player_gui then
    return
  end
  local player = game.get_player(e.player_index)
  if not player or player.opened ~= player_gui.elems.urq_window then
    return
  end
  gui.toggle_search(player_gui)
end)

script.on_event("urq-toggle-gui", function(e)
  local player_gui = gui.get(e.player_index)
  if player_gui then
    gui.toggle_visible(player_gui)
  end
end)

script.on_event(defines.events.on_lua_shortcut, function(e)
  if e.prototype_name ~= "urq-toggle-gui" then
    return
  end
  local player_gui = gui.get(e.player_index)
  if player_gui then
    gui.toggle_visible(player_gui)
  end
end)

-- Research

script.on_event(defines.events.on_research_started, function(e)
  local technology = e.research
  local force = technology.force
  local force_table = storage.forces[force.index]
  if not force_table or force_table.queue.updating_active_research then
    return -- our own mirroring of the queue
  end
  util.ensure_queue_disabled(force)

  local level = technology.level
  if research_queue.contains(force_table.queue, technology, level) then
    if force_table.queue.head.technology == technology then
      return
    end
    research_queue.remove(force_table.queue, technology, level)
  end
  research_queue.push_front(force_table.queue, technology, level)
  util.schedule_force_update(force)
end)

script.on_event(defines.events.on_research_cancelled, function(e)
  local force = e.force
  local force_table = storage.forces[force.index]
  if not force_table then
    return
  end
  util.ensure_queue_disabled(force)

  local force_queue = force_table.queue
  if force_queue.paused or force_queue.updating_active_research then
    return
  end
  local technologies = force.technologies
  for tech_name in pairs(e.research) do
    local technology = technologies[tech_name]
    research_queue.remove(force_queue, technology, technology.level)
  end
  util.schedule_force_update(force)
end)

-- Dragging in the game's research queue (technology screen)
script.on_event(defines.events.on_research_moved, function(e)
  local force_table = storage.forces[e.force.index]
  if not e.player_index or not force_table or force_table.queue.updating_active_research then
    return
  end
  research_queue.adopt_native_order(force_table.queue)
end)

script.on_event(defines.events.on_research_queued, function(e)
  local force_table = storage.forces[e.force.index]
  if not e.player_index or not force_table or force_table.queue.updating_active_research then
    return
  end
  research_queue.adopt_native_add(force_table.queue, e.research)
  util.schedule_force_update(e.force)
end)

script.on_event(defines.events.on_research_finished, function(e)
  local technology = e.research
  local force = technology.force
  local force_table = storage.forces[force.index]
  if not force_table then
    return
  end
  util.ensure_queue_disabled(force)

  local level = technology.level
  -- For multi-level techs, we want to remove the level that was just finished, not the new level.
  -- If `researched` is true, then this was the last level and it won't have incremented.
  if flib_technology.is_multilevel(technology) and not technology.researched then
    level = level - 1
  end
  if research_queue.contains(force_table.queue, technology, level) then
    research_queue.requeue_multilevel(force_table.queue)
    research_queue.remove(force_table.queue, technology, level, true)
  end

  -- Announce (a burst in one tick is a cheat or a mod unlocking everything: stay quiet)
  if force_table.auto.announce and not e.by_script then
    if force_table.last_announce_tick ~= game.tick then
      force_table.last_announce_tick, force_table.announced_this_tick = game.tick, 0
    end
    force_table.announced_this_tick = force_table.announced_this_tick + 1
    if force_table.announced_this_tick <= 3 then
      local caption = technology.localised_name
      if flib_technology.is_multilevel(technology) then
        caption = { "", caption, " ", level }
      end
      force.print({ "message.srq-research-completed", caption })
    end
  end
  auto.prune(force_table)
  force_table.auto_skip = {}

  util.schedule_force_update(force)
end)

script.on_event(defines.events.on_research_reversed, function(e)
  local technology = e.research
  local force = technology.force
  local force_table = storage.forces[force.index]
  if not force_table then
    return
  end
  util.ensure_queue_disabled(force)
  util.schedule_force_update(force)
end)

-- Settings

script.on_event(defines.events.on_runtime_mod_setting_changed, function(e)
  if e.setting == "urq-show-disabled-techs" then
    local player_gui = gui.get(e.player_index)
    if player_gui then
      gui.update(player_gui)
    end
  elseif e.setting == "urq-show-control-hints" then
    local player = game.get_player(e.player_index)
    if not player then
      return
    end
    gui.new(player)
  end
end)

-- Tick

script.on_event(defines.events.on_tick, function(e)
  dictionary.on_tick()
  -- Update force GUIs
  if next(storage.update_force_guis) then
    for force_index in pairs(storage.update_force_guis) do
      local force_table = storage.forces[force_index]
      if force_table and force_table.force.valid then
        research_queue.update_all_research_states(force_table.queue)
        research_queue.prune_researched(force_table.queue)
        auto.fill(force_table, force_table.auto_reconsider)
        force_table.auto_reconsider = false
        research_queue.update_active_research(force_table.queue)
        gui.update_force(force_table.force)
      end
    end
    storage.update_force_guis = {}
  end
  -- Filter technology lists
  for player_index, tick in pairs(storage.filter_tech_list) do
    if tick <= e.tick then
      local player_gui = gui.get(player_index)
      if player_gui and player_gui.elems.urq_window.visible then
        gui.filter_tech_list(player_gui)
      end
      storage.filter_tech_list[player_index] = nil
    end
  end
end)

--- @param force LuaForce
--- @param force_table ForceTable
--- @param current_research LuaTechnology
local function update_force_durations(force, force_table, current_research)
  local current_progress = force.research_progress
  if force_table.last_research_name ~= current_research.name then
    -- a different research than last sample: its progress isn't comparable (gave negative speeds)
    force_table.last_research_name = current_research.name
    force_table.last_research_progress = current_progress
    force_table.last_research_progress_tick = game.tick
    return
  end
  local research_time = current_research.research_unit_energy
      * flib_technology.get_research_unit_count(current_research)

  local progress_delta = current_progress - force_table.last_research_progress
  local tick_delta = game.tick - force_table.last_research_progress_tick

  if tick_delta <= 0 or progress_delta < 0 then
    force_table.last_research_progress = current_progress
    force_table.last_research_progress_tick = game.tick
    return
  end
  local normalized_speed = (progress_delta * research_time) / tick_delta

  force_table.last_research_progress = current_progress
  force_table.last_research_progress_tick = game.tick
  force_table.research_speed = normalized_speed

  research_queue.update_durations(force_table.queue)

  gui.update_force_progress(force)
end

-- The queue ran dry with nothing allowed to research: look again now and then (new packs being made,
-- a trigger technology done by hand)
-- (each look is a full refresh, ~10-15 ms in a big pack: when it keeps finding nothing, look less often - 10 s
-- doubling to 2 min - until research starts again)
local IDLE_MAX = 60 * 60 * 2
script.on_nth_tick(600, function()
  for _, force_table in pairs(storage.forces) do
    if force_table.auto.enabled and force_table.force.valid and not force_table.force.current_research then
      if game.tick >= (force_table.idle_next or 0) then
        util.schedule_force_update(force_table.force)
        force_table.idle_wait = math.min((force_table.idle_wait or 300) * 2, IDLE_MAX)
        force_table.idle_next = game.tick + force_table.idle_wait
      end
    elseif force_table.idle_wait then
      force_table.idle_wait, force_table.idle_next = nil, nil -- researching again: back to every 10 s
    end
  end
end)

script.on_nth_tick(60, function()
  for force_index, force_table in pairs(storage.forces) do
    local force = game.forces[force_index]
    if not force then
      storage.forces[force_index] = nil
      goto continue
    end
    local current_research = force.current_research
    if current_research then
      update_force_durations(force, force_table, current_research)
    end
    ::continue::
  end
end)

remote.add_interface("urq", {
  get_queue = function(force)
    local force_id = game.forces[force].index
    if not (storage.forces and storage.forces[force_id] and storage.forces[force_id].queue) then
      return {}
    end
    local queue = {}
    local node = storage.forces[force_id].queue.head
    for i = 1, storage.forces[force_id].queue.len do
      queue[i] = node.technology
      node = node.next
    end
    return queue
  end
})

--- @param force_name string
local function force_table_of(force_name)
  local force = game.forces[force_name]
  return force and storage.forces[force.index]
end

--- @param key string
--- @return fun(force_name: string, value: boolean)
local function setter(key)
  return function(force_name, value)
    local force_table = force_table_of(force_name)
    if force_table then
      force_table.auto[key] = value and true or false
      auto.changed(force_table)
    end
  end
end

-- Same calls as Auto Research's interface, so scenarios and mods that drive it keep working
remote.add_interface("auto_research", {
  enabled = setter("enabled"),
  queued_only = setter("goals_only"),
  allow_switching = setter("allow_switching"),
  announce_completed = setter("announce"),
  deprioritize_infinite_tech = setter("deprioritize_infinite"),
})

-- Read and drive the queue and auto research from other mods (and the test harness)
remote.add_interface("srq", {
  --- @return {name: string, level: uint, auto: boolean}[]
  queue = function(force_name)
    local force_table = force_table_of(force_name)
    local out = {}
    local node = force_table and force_table.queue.head
    while node do
      out[#out + 1] = { name = node.technology.name, level = node.level, auto = node.auto or false }
      node = node.next
    end
    return out
  end,
  config = function(force_name)
    local force_table = force_table_of(force_name)
    return force_table and force_table.auto
  end,
  set = function(force_name, key, value)
    local force_table = force_table_of(force_name)
    if force_table then
      force_table.auto[key] = value
      auto.changed(force_table)
    end
  end,
  add = function(force_name, list_name, tech_name, position)
    local force_table = force_table_of(force_name)
    if force_table and force_table.force.technologies[tech_name] then
      auto.add(force_table, list_name, tech_name, position)
    end
  end,
  remove = function(force_name, tech_name)
    local force_table = force_table_of(force_name)
    if force_table then
      auto.remove(force_table, tech_name)
    end
  end,
  --- @return LocalisedString? why it was refused
  push = function(force_name, tech_name, to_front)
    local force_table = force_table_of(force_name)
    local technology = force_table and force_table.force.technologies[tech_name]
    if not technology then
      return "unknown technology"
    end
    local push = to_front and research_queue.push_front or research_queue.push
    local refused = push(force_table.queue, technology, technology.level)
    util.schedule_force_update(force_table.force)
    return refused
  end,
  --- Open the window for a player, optionally on a technology
  show = function(player_index, tech_name)
    local player_gui = gui.get(player_index)
    if player_gui then
      gui.show(player_gui, tech_name)
    end
  end,
  --- Move a queued technology into another's place (as the pick-up / drop in the window does)
  -- (tests) the queue button of a technology as the hovered element, for a mocked drag
  test_hover = function(player_index, key)
    local g = gui.get(player_index)
    local el = g and g.elems.queue_table[key]
    drag_hook.test_hover(player_index, el)
    return el ~= nil
  end,
  move = function(force_name, tech_name, level, target_name, target_level)
    local force_table = force_table_of(force_name)
    local queue = force_table and force_table.queue
    local technologies = force_table and force_table.force.technologies
    if not queue or not technologies[tech_name] or not technologies[target_name] then
      return
    end
    local node = queue.lookup[flib_technology.get_leveled_name(technologies[tech_name], level)]
    local target = queue.lookup[flib_technology.get_leveled_name(technologies[target_name], target_level)]
    if node and target then
      node.auto = nil
      research_queue.move(queue, node, target)
    end
  end,
  pick = function(force_name)
    local force_table = force_table_of(force_name)
    local pick, goal = auto.pick(force_table)
    return { pick = pick and pick.name, goal = goal and goal.name }
  end,
})

-- Drag to reorder (fnative loader): chained onto the handlers above, so it goes last
local drag = require("drag")
local flib_technology_drag = require("__flib__.technology")
drag.register(function(player, payload, target)
  if type(payload) ~= "table" or payload.kind ~= "srq" or not (target and target.valid) then return end
  local self = gui.get(player.index)
  if not self then return end
  local tech = self.force.technologies[target.tags.tech_name]
  if not tech then return end
  local queue = self.force_table.queue
  local node = queue.lookup[payload.key]
  local to = queue.lookup[flib_technology_drag.get_leveled_name(tech, target.tags.level)]
  if node and to and node ~= to then
    node.auto = nil
    research_queue.move(queue, node, to)
  end
  gui.update_queue(self)
end)
