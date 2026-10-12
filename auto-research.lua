local ancestors = require("ancestors")
local flib_math = require("__flib__.math")
local flib_technology = require("__flib__.technology")

local research_queue = require("research-queue")
local util = require("util")

--- When the queue has nothing it can research, pick the next technology: goals first (their researchable
--- prerequisites, cheapest first by the strategy), then anything else unless "goals only" is set.
--- Picks are ordinary queue entries marked `auto`.
--- @class AutoResearchMod
local auto = {}

auto.strategies = { "balanced", "fast", "slow", "cheap", "expensive", "random" }

--- @class AutoConfig
--- @field enabled boolean
--- @field goals_only boolean
--- @field allow_switching boolean
--- @field announce boolean
--- @field deprioritize_infinite boolean
--- @field strategy string
--- @field allowed table<string, boolean> pack name -> false when not allowed (missing = allowed)
--- @field producing_only boolean
--- @field goals string[]
--- @field blacklist string[]

--- @return AutoConfig
function auto.new_config()
  return {
    enabled = true,
    goals_only = false,
    allow_switching = true,
    announce = true,
    deprioritize_infinite = true,
    strategy = "balanced",
    allowed = {},
    producing_only = false,
    goals = {},
    blacklist = {},
  }
end

--- @param list string[]
--- @param name string
--- @return integer?
function auto.index_of(list, name)
  for i = 1, #list do
    if list[i] == name then
      return i
    end
  end
end

--- Science packs that were made in the last hour on any surface.
--- @param force LuaForce
--- @return table<string, boolean>
function auto.producing(force)
  local out = {}
  for _, surface in pairs(game.surfaces) do
    local stats = force.get_item_production_statistics(surface)
    for _, pack in pairs(storage.science_packs or {}) do
      if not out[pack] then
        local made = stats.get_flow_count({
          name = pack,
          category = "input",
          precision_index = defines.flow_precision_index.one_hour,
          count = true,
        })
        if made > 0 then
          out[pack] = true
        end
      end
    end
  end
  return out
end

--- @param config AutoConfig
--- @param producing table<string, boolean>?
--- @param pack string
function auto.pack_allowed(config, producing, pack)
  if config.allowed[pack] == false then
    return false
  end
  return not producing or producing[pack] == true
end

--- The same check from cached data: research state "available" (enabled, prerequisites done) plus the rules.
--- @param name string
--- @param state ResearchState?
--- @param config AutoConfig
--- @param producing table<string, boolean>?
--- @param blacklisted table<string, boolean>
local function allowed_fast(name, state, config, producing, blacklisted)
  local i = storage.technology_info and storage.technology_info[name]
  if not i or state ~= 1 or i.trigger or #i.ingredients == 0 or blacklisted[name] then  -- 1 = available
    return false
  end
  for _, pack in pairs(i.ingredients) do
    if not auto.pack_allowed(config, producing, pack) then
      return false
    end
  end
  return true
end

--- Can the labs start this technology right now under the auto-research rules?
--- @param technology LuaTechnology
--- @param config AutoConfig
--- @param producing table<string, boolean>?
function auto.can_research(technology, config, producing)
  if technology.researched or not technology.enabled or technology.prototype.hidden then
    return false
  end
  local ingredients = technology.research_unit_ingredients
  if #ingredients == 0 then
    return false -- trigger technology: needs the player
  end
  for _, prerequisite in pairs(technology.prerequisites) do
    if not prerequisite.researched then
      return false
    end
  end
  for _, ingredient in pairs(ingredients) do
    if not auto.pack_allowed(config, producing, ingredient.name) then
      return false
    end
  end
  return not auto.index_of(config.blacklist, technology.name)
end

--- The player took an automatic pick out of the queue: don't pick it again until something finishes.
--- @param force_table ForceTable
--- @param technology LuaTechnology
--- @param level uint
function auto.note_removed(force_table, technology, level)
  local node = force_table.queue.lookup[flib_technology.get_leveled_name(technology, level)]
  if node and node.auto then
    force_table.auto_skip[technology.name] = true
  end
end

--- @param technology LuaTechnology
function auto.is_infinite(technology)
  return technology.prototype.max_level == flib_math.max_uint
end

--- Lower is picked first.
--- @param technology LuaTechnology
--- @param config AutoConfig
function auto.effort(technology, config)
  local count = math.max(flib_technology.get_research_unit_count(technology), 1)
  local time = math.max(technology.research_unit_energy, 1)
  local packs = 0
  for _, ingredient in pairs(technology.research_unit_ingredients) do
    packs = packs + ingredient.amount
  end
  packs = math.max(packs, 1)
  local strategy = config.strategy
  local effort
  if strategy == "fast" then
    effort = time * count
  elseif strategy == "slow" then
    effort = -time * count
  elseif strategy == "cheap" then
    effort = packs * count
  elseif strategy == "expensive" then
    effort = -packs * count
  elseif strategy == "random" then
    effort = math.random(1, 999)
  else -- balanced
    effort = count * time * packs
  end
  if config.deprioritize_infinite and auto.is_infinite(technology) then
    -- after every finite tech, whatever the sign of the effort
    effort = effort + 1e15
  end
  return effort
end

--- @param candidates LuaTechnology[]
--- @param config AutoConfig
--- @return LuaTechnology?
local function least_effort(candidates, config)
  local best, best_effort
  for _, technology in pairs(candidates) do
    local effort = auto.effort(technology, config)
    if not best_effort or effort < best_effort then
      best, best_effort = technology, effort
    end
  end
  return best
end

--- The technology auto research would start now, and the goal it works towards (if any).
--- @param force_table ForceTable
--- @return LuaTechnology?, LuaTechnology?
function auto.pick(force_table)
  local config = force_table.auto
  local force = force_table.force
  local technologies = force.technologies
  local producing = config.producing_only and auto.producing(force) or nil
  local skip = force_table.auto_skip or {}
  local states = force_table.research_states
  local blacklisted = {}
  for _, name in pairs(config.blacklist) do
    blacklisted[name] = true
  end
  if storage.technology_info and states then
    -- from cached data and the states the queue just computed
    for _, goal_name in pairs(config.goals) do
      if states[goal_name] ~= 4 then  -- 4 = researched
        local candidates = {}
        if not skip[goal_name] and allowed_fast(goal_name, states[goal_name], config, producing, blacklisted) then
          candidates[#candidates + 1] = technologies[goal_name]
        end
        for _, name in pairs(ancestors.of(goal_name) or {}) do
          if not skip[name] and allowed_fast(name, states[name], config, producing, blacklisted) then
            candidates[#candidates + 1] = technologies[name]
          end
        end
        local best = least_effort(candidates, config)
        if best then
          return best, technologies[goal_name]
        end
      end
    end
    if config.goals_only then
      return nil
    end
    local candidates = {}
    for name, state in pairs(states) do
      if state == 1 and not skip[name] and allowed_fast(name, state, config, producing, blacklisted) then
        candidates[#candidates + 1] = technologies[name]
      end
    end
    return least_effort(candidates, config)
  end

  for _, goal_name in pairs(config.goals) do
    local goal = technologies[goal_name]
    if goal and not goal.researched then
      local candidates = {}
      if auto.can_research(goal, config, producing) and not skip[goal.name] then
        candidates[#candidates + 1] = goal
      end
      for _, name in pairs(ancestors.of(goal_name) or {}) do
        local technology = technologies[name]
        if technology and not skip[name] and auto.can_research(technology, config, producing) then
          candidates[#candidates + 1] = technology
        end
      end
      local best = least_effort(candidates, config)
      if best then
        return best, goal
      end
    end
  end

  if config.goals_only then
    return nil
  end
  local candidates = {}
  for _, technology in pairs(technologies) do
    if not skip[technology.name] and auto.can_research(technology, config, producing) then
      candidates[#candidates + 1] = technology
    end
  end
  return least_effort(candidates, config)
end

--- @param queue ResearchQueue
local function has_auto(queue)
  local node = queue.head
  while node do
    if node.auto then
      return true
    end
    node = node.next
  end
  return false
end

--- @param queue ResearchQueue
local function remove_auto(queue)
  local node = queue.head
  while node do
    local next_node = node.next
    if node.auto then
      research_queue.remove(queue, node.technology, node.level, true)
    end
    node = next_node
  end
end

--- Keep the queue busy. `reconsider`: the rules changed, so an automatic pick may be replaced.
--- @param force_table ForceTable
--- @param reconsider boolean?
function auto.fill(force_table, reconsider)
  local config = force_table.auto
  local queue = force_table.queue
  if not config.enabled then
    if has_auto(queue) then
      remove_auto(queue)
    end
    return
  end
  if queue.paused then
    return
  end

  local startable = research_queue.first_startable(queue)
  if startable and (not startable.auto or (config.allow_switching and research_queue.first_startable(queue, true))) then
    -- the player's own queue has work: automatic picks finish first, or go if switching is allowed
    if config.allow_switching and has_auto(queue) then
      remove_auto(queue)
    end
    return
  end
  if startable and startable.auto then
    if not (reconsider and config.allow_switching) then
      return
    end
    local pick = auto.pick(force_table)
    if pick and pick.name == startable.technology.name then
      return
    end
    remove_auto(queue)
  end

  local pick = auto.pick(force_table)
  if not pick then
    return
  end
  local level = pick.level
  if research_queue.push(queue, pick, level) then
    return -- refused (queue full and the like)
  end
  local node = queue.lookup[flib_technology.get_leveled_name(pick, level)]
  if node then
    node.auto = true
  end
end

--- Drop researched goals and blacklist entries.
--- @param force_table ForceTable
function auto.prune(force_table)
  local config = force_table.auto
  local technologies = force_table.force.technologies
  for _, list in pairs({ config.goals, config.blacklist }) do
    for i = #list, 1, -1 do
      local technology = technologies[list[i]]
      if not technology or technology.researched then
        table.remove(list, i)
      end
    end
  end
end

--- @param force_table ForceTable
function auto.changed(force_table)
  force_table.auto_reconsider = true
  util.schedule_force_update(force_table.force)
end

--- @param force_table ForceTable
--- @param list_name "goals"|"blacklist"
--- @param name string
--- @param position integer?
function auto.add(force_table, list_name, name, position)
  local config = force_table.auto
  for _, other in pairs({ "goals", "blacklist" }) do
    local i = auto.index_of(config[other], name)
    if i then
      table.remove(config[other], i)
    end
  end
  local list = config[list_name]
  table.insert(list, math.min(position or (#list + 1), #list + 1), name)
  auto.changed(force_table)
end

--- @param force_table ForceTable
--- @param name string
function auto.remove(force_table, name)
  local config = force_table.auto
  for _, list_name in pairs({ "goals", "blacklist" }) do
    local i = auto.index_of(config[list_name], name)
    if i then
      table.remove(config[list_name], i)
    end
  end
  auto.changed(force_table)
end

--- @param force_table ForceTable
--- @param name string
--- @param delta integer -1 = up, 1 = down
function auto.move_goal(force_table, name, delta)
  local goals = force_table.auto.goals
  local i = auto.index_of(goals, name)
  if not i then
    return
  end
  local j = flib_math.clamp(i + delta, 1, #goals)
  goals[i], goals[j] = goals[j], goals[i]
  auto.changed(force_table)
end

--- Comma separated tech names from a per-player setting (unknown and researched ones are skipped).
--- @param force_table ForceTable
--- @param list_name "goals"|"blacklist"
--- @param value string
function auto.add_from_setting(force_table, list_name, value)
  local technologies = force_table.force.technologies
  for name in string.gmatch(value or "", "[^,]+") do
    name = string.gsub(name, "%s+", "")
    local technology = technologies[name]
    if technology and technology.enabled and not technology.researched
        and not auto.index_of(force_table.auto[list_name], name) then
      auto.add(force_table, list_name, name)
    end
  end
end

return auto
