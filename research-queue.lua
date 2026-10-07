local ancestors = require("ancestors")
local format = require("__flib__.format")
local math = require("__flib__.math")
local flib_technology = require("__flib__.technology")

local constants = require("constants")
local util = require("util")

--- @class ResearchQueueNode
--- @field technology LuaTechnology
--- @field level uint
--- @field duration string
--- @field key string
--- @field next ResearchQueueNode?
--- @field auto boolean? picked by auto research
--- @field notified boolean? "needs player action" was printed

--- @class TechnologyAndLevel
--- @field technology LuaTechnology
--- @field level uint

--- @class ResearchQueue
--- @field force LuaForce
--- @field force_table ForceTable
--- @field head ResearchQueueNode?
--- @field len uint
--- @field lookup table<string, ResearchQueueNode>
--- @field paused boolean
--- @field requeue_multilevel boolean
--- @field updating_active_research boolean

--- @class ResearchQueueMod
local research_queue = {}

--- @param self ResearchQueue
function research_queue.clear(self)
  while self.head do
    research_queue.remove(self, self.head.technology, self.head.level)
  end
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level boolean|uint?
--- @return boolean
function research_queue.contains(self, technology, level)
  if not flib_technology.is_multilevel(technology) then
    return not not self.lookup[technology.name]
  end

  local base_name = flib_technology.get_base_name(technology)
  if level and type(level) == "number" then
    -- This level
    return not not self.lookup[base_name .. "-" .. level]
  elseif level and technology.prototype.max_level ~= math.max_uint then
    local base_key = base_name .. "-"
    -- All levels
    for i = technology.level, technology.prototype.max_level do
      if not self.lookup[base_key .. i] then
        return false
      end
    end
    return true
  else
    -- Any level
    for key in pairs(self.lookup) do
      if string.find(key, base_name, nil, true) then
        return true
      end
    end
    return false
  end
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @return uint
function research_queue.get_highest_level(self, technology)
  local node = self.head
  local highest = 0
  while node do
    if node.technology == technology then
      highest = math.max(node.level, highest)
    end
    node = node.next
  end
  return highest
end

--- @param technology LuaTechnology
local function is_trigger_research(technology)
  return technology.prototype.research_trigger ~= nil
end

--- @param technology LuaTechnology
local function are_prereqs_satisfied(technology)
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched then
      return false
    end
  end
  return true
end

--- @param technology LuaTechnology
--- @param queue ResearchQueue
local function are_prereqs_satisfied_or_queued(technology, queue)
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched and not research_queue.contains(queue, prerequisite, true) then
      return false
    end
  end
  return true
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @return ResearchState
function research_queue.get_research_state(self, technology)
  if technology.researched then
    return constants.research_state.researched
  end
  if technology.prototype.hidden or not technology.enabled then
    return constants.research_state.disabled
  end
  if are_prereqs_satisfied(technology) then
    return constants.research_state.available
  end
  if are_prereqs_satisfied_or_queued(technology, self) then
    return constants.research_state.conditionally_available
  end
  return constants.research_state.not_available
end

--- Add a technology and its prerequisites to the queue.
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
--- @param index integer?
--- @return LocalisedString?
local function push(self, technology, level, index)
  -- Update flag and length
  self.len = self.len + 1
  -- Add to linked list
  local key = flib_technology.get_leveled_name(technology, level)
  --- @type ResearchQueueNode
  local new_node = { technology = technology, level = level, duration = "[img=infinity]", key = key }
  self.lookup[key] = new_node
  if not self.head or index == 1 then
    new_node.next = self.head
    self.head = new_node
  elseif index then
    local node = self.head
    while node and node.next and index > 2 do
      index = index - 1
      node = node.next
    end
    -- This shouldn't ever fail...
    if node then
      new_node.next = node.next
      node.next = new_node
    end
  else
    local node = self.head
    while node and node.next do
      node = node.next
    end
    -- This shouldn't ever fail...
    node.next = new_node
  end

  util.schedule_force_update(self.force)
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @return LocalisedString?
function research_queue.instant_research(self, technology)
  local research_state = self.force_table.research_states[technology.name]
  if research_state == constants.research_state.researched then
    return { "message.urq-already-researched" }
  elseif is_trigger_research(technology) then
    return { "message.urq-unable-to-queue" }
  end
  if research_state == constants.research_state.available then
    technology.researched = true
    return
  end
  local prerequisites = ancestors.of(technology.name) or {}
  local technologies = self.force.technologies
  for i = 1, #prerequisites do
    local prerequisite = technologies[prerequisites[i]]
    if not prerequisite.researched then
      prerequisite.researched = true
    end
  end
  technology.researched = true
end

--- This does not account for prerequisites
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
function research_queue.move_to_front(self, technology, level)
  local node, prev = self.head, nil
  while node and (node.technology ~= technology or node.level ~= level) do
    prev = node
    node = node.next
  end
  if not node or not prev then
    return
  end
  prev.next = node.next
  node.next = self.head
  self.head = node
end

--- @param force LuaForce
--- @param force_table ForceTable
--- @return ResearchQueue
function research_queue.new(force, force_table)
  --- @type ResearchQueue
  return {
    force = force,
    force_table = force_table,
    --- @type ResearchQueueNode?
    head = nil,
    len = 0,
    --- @type table<string, ResearchQueueNode>
    lookup = {},
    paused = false,
    requeue_multilevel = false,
    updating_active_research = true,
  }
end

--- @param to_research TechnologyAndLevel[]
--- @param technology LuaTechnology
--- @param level uint?
--- @param queue ResearchQueue?
local function add_technology(to_research, technology, level, queue)
  local lower = technology.level
  if queue then
    lower = math.clamp(research_queue.get_highest_level(queue, technology) + 1, lower, technology.prototype.max_level) --[[@as uint]]
  end
  for i = lower, level or technology.prototype.max_level do
    --- @cast i uint
    to_research[#to_research + 1] = { technology = technology, level = i }
  end
end

--- Add a technology and its prerequisites to the queue.
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
--- @return LocalisedString?
function research_queue.push(self, technology, level)
  local research_state = self.force_table.research_states[technology.name]
  if research_state == constants.research_state.researched then
    return { "message.urq-already-researched" }
  elseif is_trigger_research(technology) then
    return { "message.urq-unable-to-queue" }
  elseif research_state == constants.research_state.disabled then
    return { "message.urq-tech-is-disabled" }
  elseif research_queue.contains(self, technology, level) then
    return { "message.urq-already-in-queue" }
  end
  --- @type TechnologyAndLevel[]
  local to_research = {}
  if research_state == constants.research_state.not_available then
    -- Add all prerequisites to research this technology ASAP
    local technologies = self.force.technologies
    local technology_prerequisites = ancestors.of(technology.name) or {}
    for i = 1, #technology_prerequisites do
      local prerequisite_name = technology_prerequisites[i]
      local prerequisite = technologies[prerequisite_name]
      local prerequisite_research_state = self.force_table.research_states[prerequisite_name]
      if prerequisite_research_state == constants.research_state.disabled then
        return { "message.urq-has-disabled-prerequisites" }
      end
      if
          not research_queue.contains(self, prerequisite, true)
          and prerequisite_research_state ~= constants.research_state.researched
      then
        add_technology(to_research, prerequisite)
      end
    end
  end
  add_technology(to_research, technology, level, self)
  -- Check for errors
  local num_to_research = #to_research
  if num_to_research > constants.queue_limit then
    return { "message.urq-too-many-unresearched-prerequisites" }
  else
    local len = self.len
    -- It shouldn't ever be greater... right?
    if len >= constants.queue_limit then
      return { "message.urq-queue-is-full" }
    elseif len + num_to_research > constants.queue_limit then
      return { "message.urq-too-many-prerequisites-queue-full" }
    end
  end
  for i = 1, #to_research do
    local to_research = to_research[i]
    push(self, to_research.technology, to_research.level)
  end
end

--- Add a technology and its prerequisites to the front of the queue, moving prerequisites if required.
--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
function research_queue.push_front(self, technology, level)
  local research_state = self.force_table.research_states[technology.name]
  if research_state == constants.research_state.researched then
    return { "message.urq-already-researched" }
  elseif is_trigger_research(technology) then
    return { "message.urq-unable-to-queue" }
  end
  --- @type TechnologyAndLevel[]
  local to_research = {}
  --- @type TechnologyAndLevel[]
  local to_move = {}
  -- Add all prerequisites to research this technology ASAP
  local technologies = self.force.technologies
  local technology_prerequisites = ancestors.of(technology.name) or {}
  for i = 1, #technology_prerequisites do
    local prerequisite_name = technology_prerequisites[i]
    local prerequisite = technologies[prerequisite_name]
    local prerequisite_research_state = self.force_table.research_states[prerequisite_name]
    local in_queue = research_queue.contains(self, prerequisite, true)
    if in_queue then
      add_technology(to_move, prerequisite)
    elseif prerequisite_research_state ~= constants.research_state.researched then
      add_technology(to_research, prerequisite)
    end
  end
  -- Move higher levels of this tech forward
  if flib_technology.is_multilevel(technology) and research_queue.contains(self, technology, true) then
    local highest = research_queue.get_highest_level(self, technology)
    add_technology(to_move, technology, highest)
  end
  if research_queue.contains(self, technology, true) then
    add_technology(to_move, technology)
  else
    add_technology(to_research, technology, level, self)
  end
  -- Check for errors
  local num_to_research = #to_research
  if num_to_research > constants.queue_limit then
    return { "message.urq-too-many-unresearched-prerequisites" }
  else
    local len = self.len
    -- It shouldn't ever be greater... right?
    if len >= constants.queue_limit then
      return { "message.urq-queue-is-full" }
    elseif len + num_to_research > constants.queue_limit then
      return { "message.urq-too-many-prerequisites-queue-full" }
    end
  end
  local num_to_move = #to_move
  for i = num_to_move, 1, -1 do
    local to_move = to_move[i]
    research_queue.move_to_front(self, to_move.technology, to_move.level)
  end
  for i = 1, #to_research do
    local to_research = to_research[i]
    push(self, to_research.technology, to_research.level, num_to_move + i)
  end
  util.schedule_force_update(self.force)
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param level uint
--- @param skip_validation boolean?
--- @return boolean?
function research_queue.remove(self, technology, level, skip_validation)
  local key = flib_technology.get_leveled_name(technology, level)
  if not self.lookup[key] then
    return
  end
  -- Remove from linked list
  local node, prev = self.head, nil
  while node and (node.technology ~= technology or node.level ~= level) do
    prev = node
    node = node.next
  end
  if not node then
    return
  end
  -- Remove node and decrement length
  self.lookup[key] = nil
  self.len = self.len - 1
  if node == self.head then
    self.head = node.next
  else
    prev.next = node.next
  end

  util.schedule_force_update(self.force)

  if skip_validation then
    return
  end
  -- Remove descendants
  local technologies = self.force.technologies
  local descendants = storage.technology_descendants[technology.name]
  local is_multilevel = flib_technology.is_multilevel(technology)
  if descendants then
    for _, descendant_name in pairs(descendants) do
      local descendant = technologies[descendant_name]
      local level = descendant.level
      if is_multilevel then
        level = level + 1
      end
      if research_queue.contains(self, descendant, level) then
        research_queue.remove(self, descendant, level)
      end
    end
  end
  -- Remove all levels above this one
  if is_multilevel and technology.level <= level then
    local node = self.head
    while node do
      if node.technology == technology and node.level > level then
        research_queue.remove(self, technology, node.level)
      end
      node = node.next
    end
  end
end

--- @param self ResearchQueue
function research_queue.requeue_multilevel(self)
  if not self.requeue_multilevel then
    return
  end
  local head = self.head
  if not head then
    return
  end
  local technology = head.technology
  if not flib_technology.is_multilevel(technology) then
    return
  end
  local next_level = research_queue.get_highest_level(self, technology) + 1
  if next_level > technology.prototype.max_level then
    return
  end
  research_queue.push(self, technology, next_level)
end

--- @param self ResearchQueue
function research_queue.toggle_paused(self)
  self.paused = not self.paused
  research_queue.update_active_research(self)
end

--- @param self ResearchQueue
function research_queue.toggle_requeue_multilevel(self)
  self.requeue_multilevel = not self.requeue_multilevel
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
function research_queue.unresearch(self, technology)
  local technologies = self.force.technologies
  local research_states = self.force_table.research_states

  --- @param technology LuaTechnology
  local function propagate(technology)
    local descendants = storage.technology_descendants[technology.name] or {}
    for i = 1, #descendants do
      local descendant_name = descendants[i]
      if research_states[descendant_name] == constants.research_state.researched then
        local descendant_data = technologies[descendant_name]
        propagate(descendant_data)
      end
    end
    technology.researched = false
  end

  propagate(technology)
end

--- Labs can work on this technology now (not a trigger technology, prerequisites done).
--- @param technology LuaTechnology
function research_queue.is_startable(technology)
  return not technology.researched
    and technology.enabled
    and #technology.research_unit_ingredients > 0
    and are_prereqs_satisfied(technology)
end

--- The first queued technology the labs can work on.
--- @param self ResearchQueue
--- @param players_only boolean? skip automatic picks
--- @return ResearchQueueNode?
function research_queue.first_startable(self, players_only)
  local node = self.head
  while node do
    if research_queue.is_startable(node.technology) and not (players_only and node.auto) then
      return node
    end
    node = node.next
  end
end

--- Drop entries that got researched some other way (a script, a trigger, another mod).
--- @param self ResearchQueue
function research_queue.prune_researched(self)
  local node = self.head
  while node do
    local next_node = node.next
    local technology = node.technology
    if technology.researched or (flib_technology.is_multilevel(technology) and node.level < technology.level) then
      research_queue.remove(self, technology, node.level, true)
    end
    node = next_node
  end
end

--- Research the first queued technology the labs can work on; trigger technologies (and whatever waits on
--- them) stay in the queue until the player completes them. Each blocked entry is announced once.
--- @param self ResearchQueue
function research_queue.update_active_research(self)
  local target = not self.paused and research_queue.first_startable(self) or nil
  if not self.paused then
    local node = self.head
    while node and node ~= target do
      if not node.notified and #node.technology.research_unit_ingredients == 0 then
        node.notified = true
        for _, player in pairs(self.force.players) do
          player.print({ "", { "message.urq-requires-player-action" }, node.technology.prototype.localised_name })
        end
      end
      node = node.next
    end
  end
  -- Mirror the front of the queue into the game's own research queue, so it can be reordered by dragging
  -- in the technology screen (on_research_moved brings that order back here)
  local list = research_queue.native_list(self)
  local native = self.force.research_queue
  local same = #native == #list
  for i = 1, same and #list or 0 do
    if native[i].name ~= list[i].technology.name then
      same = false
      break
    end
  end
  if not same then
    local technologies = {}
    for i, node in pairs(list) do
      technologies[i] = node.technology
    end
    self.updating_active_research = true
    self.force.research_queue = technologies
    self.updating_active_research = false
    self.force_table.last_research_progress = list[1]
        and flib_technology.get_research_progress(list[1].technology, list[1].level) or 0
  end
  self.force_table.last_research_progress_tick = game.tick
end

research_queue.native_limit = 7

--- The front of the queue as the game's research queue can hold it: entries the labs can work on once the
--- ones before them are done (no trigger technologies, levels in order), at most `native_limit`.
--- @param self ResearchQueue
--- @return ResearchQueueNode[]
function research_queue.native_list(self)
  local list, planned = {}, {}
  if self.paused then
    return list
  end
  local node = self.head
  while node and #list < research_queue.native_limit do
    local technology = node.technology
    local ok = not technology.researched and technology.enabled and #technology.research_unit_ingredients > 0
    if ok then
      for _, prerequisite in pairs(technology.prerequisites) do
        if not prerequisite.researched and not planned[prerequisite.name] then
          ok = false
          break
        end
      end
    end
    if ok and flib_technology.is_multilevel(technology) then
      ok = node.level == (planned[technology.name] or (technology.level - 1)) + 1
    end
    if ok then
      list[#list + 1] = node
      planned[technology.name] = node.level
    end
    node = node.next
  end
  return list
end

--- @param self ResearchQueue
--- @return ResearchQueueNode[]
local function to_array(self)
  local array, node = {}, self.head
  while node do
    array[#array + 1] = node
    node = node.next
  end
  return array
end

--- @param self ResearchQueue
--- @param array ResearchQueueNode[]
local function from_array(self, array)
  self.head = array[1]
  for i = 1, #array do
    array[i].next = array[i + 1]
  end
  util.schedule_force_update(self.force)
end

--- @param array ResearchQueueNode[]
--- @param node ResearchQueueNode
local function index_of(array, node)
  for i = 1, #array do
    if array[i] == node then
      return i
    end
  end
end

--- `later` must stay after `earlier` (a prerequisite, or a lower level of the same technology)
--- @param later ResearchQueueNode
--- @param earlier ResearchQueueNode
local function needs(later, earlier)
  if later.technology == earlier.technology then
    return later.level > earlier.level
  end
  local name = earlier.technology.name
  for _, prerequisite in pairs(ancestors.of(later.technology.name) or {}) do
    if prerequisite == name then
      return true
    end
  end
  return false
end

--- Move `node` into `target`'s place. Queued prerequisites move in front of it when it goes earlier, queued
--- technologies that need it move behind it when it goes later, so the queue stays researchable in order.
--- @param self ResearchQueue
--- @param node ResearchQueueNode
--- @param target ResearchQueueNode
function research_queue.move(self, node, target)
  local array = to_array(self)
  local from, to = index_of(array, node), index_of(array, target)
  if not from or not to or from == to then
    return
  end
  table.remove(array, from)
  to = index_of(array, target) + (from < to and 1 or 0)
  table.insert(array, to, node)
  local moved = {}
  if from > to then
    for i = to + 1, #array do
      if needs(node, array[i]) then
        moved[#moved + 1] = array[i]
      end
    end
  else
    for i = 1, to - 1 do
      if needs(array[i], node) then
        moved[#moved + 1] = array[i]
      end
    end
  end
  for _, other in pairs(moved) do
    table.remove(array, index_of(array, other))
  end
  local at = index_of(array, node) + (from > to and 0 or 1)
  for i, other in pairs(moved) do
    table.insert(array, at + i - 1, other)
  end
  from_array(self, array)
end

--- The player reordered the game's research queue (dragging in the technology screen): put the mirrored
--- entries in that order, in the places they hold in this queue.
--- @param self ResearchQueue
function research_queue.adopt_native_order(self)
  local array = to_array(self)
  local used, ordered = {}, {}
  for _, technology in pairs(self.force.research_queue) do
    local best
    for _, node in pairs(array) do
      if not used[node] and node.technology.name == technology.name and (not best or node.level < best.level) then
        best = node
      end
    end
    if best then
      used[best] = true
      ordered[#ordered + 1] = best
    end
  end
  local k = 0
  for i = 1, #array do
    if used[array[i]] then
      k = k + 1
      array[i] = ordered[k]
    end
  end
  from_array(self, array)
end

--- The player added a technology through the game's research queue: queue it here, right behind the
--- entries mirrored there.
--- @param self ResearchQueue
--- @param technology LuaTechnology
function research_queue.adopt_native_add(self, technology)
  local level = math.max(technology.level, research_queue.get_highest_level(self, technology) + 1)
  if level > technology.prototype.max_level or research_queue.contains(self, technology, level) then
    return
  end
  local anchor = research_queue.native_list(self)
  anchor = anchor[#anchor]
  if research_queue.push(self, technology, level) then
    return
  end
  local node = self.lookup[flib_technology.get_leveled_name(technology, level)]
  if not node or not anchor or not anchor.next or anchor.next == node then
    return
  end
  local array = to_array(self)
  table.remove(array, index_of(array, node))
  table.insert(array, index_of(array, anchor) + 1, node)
  from_array(self, array)
end

--- @param self ResearchQueue
function research_queue.update_durations(self)
  local speed = self.force_table.research_speed
  local duration = 0
  local node = self.head
  while node do
    if speed == 0 then
      node.duration = "[img=infinity]"
    else
      local technology, level = node.technology, node.level
      local progress = flib_technology.get_research_progress(technology, level)
      duration = duration
          + (1 - progress)
          * flib_technology.get_research_unit_count(technology, node.level)
          * technology.research_unit_energy
          / speed
      node.duration = format.time(duration --[[@as uint]])
    end
    node = node.next
  end
end

--- @param self ResearchQueue
function research_queue.update_all_research_states(self)
  local info = storage.technology_info
  local technologies = self.force.technologies
  if not info then  -- before the cache exists (first tick of an old save)
    for _, technology in pairs(technologies) do
      research_queue.set_research_state(self, technology, research_queue.get_research_state(self, technology))
    end
    return
  end
  local researched = {}
  for name, technology in pairs(technologies) do
    researched[name] = technology.researched
  end
  local states = constants.research_state
  for name, technology in pairs(technologies) do
    local i = info[name]
    local state
    if researched[name] then
      state = states.researched
    elseif not i or i.hidden or not technology.enabled then
      state = i and states.disabled or research_queue.get_research_state(self, technology)
    else
      local all, all_or_queued = true, true
      for _, p in pairs(i.prereqs) do
        if not researched[p] then
          all = false
          if not research_queue.contains(self, technologies[p], true) then
            all_or_queued = false
            break
          end
        end
      end
      state = all and states.available or all_or_queued and states.conditionally_available or states.not_available
    end
    research_queue.set_research_state(self, technology, state)
  end
end

--- @param self ResearchQueue
--- @param technology LuaTechnology
--- @param new_state ResearchState
function research_queue.set_research_state(self, technology, new_state)
  local research_states = self.force_table.research_states
  local previous_state = research_states[technology.name]
  if new_state ~= previous_state then
    local order = storage.technology_order[technology.name]
    local groups = self.force_table.technology_groups
    groups[previous_state][order] = nil
    groups[new_state][order] = technology
    research_states[technology.name] = new_state
  end
end

--- @param self ResearchQueue
function research_queue.verify_integrity(self)
  local old_head = self.head
  self.head, self.lookup, self.len = nil, {}, 0
  local node = old_head
  local technologies = self.force.technologies
  while node do
    local old_technology, old_level = node.technology, node.level
    if old_technology.valid then
      local technology = technologies[old_technology.name]
      -- keep the queued level (this used to re-queue every level as the first one, losing the rest)
      if old_level >= technology.level and old_level <= technology.prototype.max_level then
        research_queue.push(self, technology, old_level)
        local key = flib_technology.get_leveled_name(technology, old_level)
        if self.lookup[key] then
          self.lookup[key].auto = node.auto
        end
      end
    end
    node = node.next
  end
end

return research_queue
