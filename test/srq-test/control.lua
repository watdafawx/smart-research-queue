-- Headless checks for Smart Research Queue: runs a script of steps, one every 10 ticks, writes srq-test.txt
local F = "player"
local out = {}
local step = 0

local function check(name, ok, detail)
  out[#out + 1] = (ok and "PASS " or "FAIL ") .. name .. (detail and (" :: " .. tostring(detail)) or "")
end

local function queue()
  return remote.call("srq", "queue", F)
end

local function queue_str()
  local t = {}
  for _, n in pairs(queue()) do
    t[#t + 1] = n.name .. (n.level > 1 and (":" .. n.level) or "") .. (n.auto and "*" or "")
  end
  return table.concat(t, ",")
end

local function current()
  local r = game.forces[F].current_research
  return r and r.name
end

local function has_auto()
  for _, n in pairs(queue()) do
    if n.auto then
      return true
    end
  end
  return false
end

local function startable(t)
  if t.researched or not t.enabled or t.prototype.hidden or #t.research_unit_ingredients == 0 then
    return false
  end
  for _, p in pairs(t.prerequisites) do
    if not p.researched then
      return false
    end
  end
  return true
end

local function cheap_effort(t)
  local packs = 0
  for _, i in pairs(t.research_unit_ingredients) do
    packs = packs + i.amount
  end
  return math.max(packs, 1) * math.max(t.research_unit_count, 1)
end

-- research every trigger technology whose prerequisites are done, repeatedly
local function finish_triggers(limit)
  local force = game.forces[F]
  for _ = 1, limit or 20 do
    local changed = false
    for _, t in pairs(force.technologies) do
      if not t.researched and t.enabled and t.prototype.research_trigger then
        local ready = true
        for _, p in pairs(t.prerequisites) do
          if not p.researched then
            ready = false
          end
        end
        if ready then
          t.researched = true
          changed = true
        end
      end
    end
    if not changed then
      return
    end
  end
end

local trigger_case = {}

local steps = {
  function()
    check("fresh start: nothing startable, no research", current() == nil, current())
  end,
  function()
    finish_triggers(20)
  end,
  function()
    local q = queue()
    check("auto picks once something is startable", current() ~= nil and q[1] and q[1].auto, queue_str())
    remote.call("srq", "set", F, "strategy", "cheap")
  end,
  function()
    local force = game.forces[F]
    local best
    for _, t in pairs(force.technologies) do
      if startable(t) and not (t.prototype.max_level == 4294967295) then
        local e = cheap_effort(t)
        if not best or e < best then
          best = e
        end
      end
    end
    local cur = force.current_research
    check("strategy cheap re-picks the cheapest", cur and cheap_effort(cur) == best,
      (cur and cur.name or "nil") .. " effort " .. (cur and cheap_effort(cur) or -1) .. " best " .. tostring(best))
    remote.call("srq", "add", F, "goals", "logistic-science-pack")
  end,
  function()
    local force = game.forces[F]
    local goal = force.technologies["logistic-science-pack"]
    local allowed = { [goal.name] = true }
    local function walk(t)
      for _, p in pairs(t.prerequisites) do
        if not p.researched and not allowed[p.name] then
          allowed[p.name] = true
          walk(p)
        end
      end
    end
    walk(goal)
    local pick = remote.call("srq", "pick", F)
    check("goal steers the pick", current() and allowed[current()] and pick.goal == goal.name,
      tostring(current()) .. " goal " .. tostring(pick.goal))
  end,
  function()
    -- the player queues something: the automatic pick gives way (allow switching is on)
    local force = game.forces[F]
    for _, t in pairs(force.technologies) do
      if startable(t) and t.name ~= current() then
        trigger_case.user = t.name
        break
      end
    end
    remote.call("srq", "push", F, trigger_case.user)
  end,
  function()
    check("player's queue goes first, auto pick removed", current() == trigger_case.user and not has_auto(),
      queue_str() .. " current " .. tostring(current()))
    game.forces[F].technologies[trigger_case.user].researched = true
  end,
  function()
    local q = queue()
    check("auto resumes after the player's queue", q[1] and q[1].auto and current() == q[1].name, queue_str())
    remote.call("srq", "set", F, "allowed", { ["automation-science-pack"] = false })
  end,
  function()
    check("blocking red science stops auto research", current() == nil and not has_auto(),
      queue_str() .. " current " .. tostring(current()))
    remote.call("srq", "set", F, "allowed", {})
  end,
  function()
    check("unblocking resumes", current() ~= nil and has_auto(), queue_str())
    remote.call("srq", "set", F, "enabled", false)
  end,
  function()
    check("turning auto off clears its pick", current() == nil and not has_auto(), queue_str())
    remote.call("srq", "set", F, "enabled", true)
    remote.call("srq", "set", F, "goals_only", true)
    remote.call("srq", "remove", F, "logistic-science-pack")
  end,
  function()
    check("goals only with no goals waits", current() == nil, queue_str())
    remote.call("srq", "set", F, "goals_only", false)
  end,
  function()
    -- a tech behind an unfinished trigger technology: the trigger tech waits in the queue, labs work on
    -- something else meanwhile. Set it up: research the trigger tech's prerequisites and the tech's others.
    local force = game.forces[F]
    local function research_up_to(t)
      for _, p in pairs(t.prerequisites) do
        if not p.researched then
          research_up_to(p)
          p.researched = true
        end
      end
    end
    for _, t in pairs(force.technologies) do
      if not t.researched and t.enabled and not t.prototype.hidden and #t.research_unit_ingredients > 0 then
        for _, p in pairs(t.prerequisites) do
          if not p.researched and p.prototype.research_trigger and p.enabled then
            trigger_case.tech, trigger_case.trigger = t.name, p.name
            break
          end
        end
      end
      if trigger_case.tech then
        break
      end
    end
    check("found a tech behind a trigger tech", trigger_case.tech ~= nil,
      tostring(trigger_case.tech) .. " <- " .. tostring(trigger_case.trigger))
    if trigger_case.tech then
      local tech, trig = force.technologies[trigger_case.tech], force.technologies[trigger_case.trigger]
      research_up_to(trig)
      for _, p in pairs(tech.prerequisites) do
        if p ~= trig and not p.researched then
          research_up_to(p)
          p.researched = true
        end
      end
    end
  end,
  function()
    if trigger_case.tech then
      local refused = remote.call("srq", "push", F, trigger_case.tech)
      check("queueing it is accepted", refused == nil, serpent.line(refused))
    end
  end,
  function()
    if not trigger_case.tech then
      return
    end
    local cur = current()
    check("labs work on an auto pick while the trigger tech waits",
      cur ~= nil and cur ~= trigger_case.tech and cur ~= trigger_case.trigger and has_auto(), queue_str() .. " current " .. tostring(cur))
    game.forces[F].technologies[trigger_case.trigger].researched = true
  end,
  function()
    if not trigger_case.tech then
      return
    end
    check("trigger done: the queued tech starts, auto pick gives way", current() == trigger_case.tech and not has_auto(),
      queue_str() .. " current " .. tostring(current()))
  end,
  function()
    -- multi-level: queue two levels of a leveled tech if one is startable
    local force = game.forces[F]
    for _, t in pairs(force.technologies) do
      if t.prototype.max_level > t.prototype.level and startable(t) then
        remote.call("srq", "push", F, t.name)
        trigger_case.multi = t.name
        break
      end
    end
    check("strategies all run", true)
    for _, s in pairs({ "balanced", "fast", "slow", "expensive", "random" }) do
      remote.call("srq", "set", F, "strategy", s)
      local ok, err = pcall(remote.call, "srq", "pick", F)
      check("pick with " .. s, ok, err)
    end
    remote.call("srq", "set", F, "producing_only", true)
    local ok, err = pcall(remote.call, "srq", "pick", F)
    check("pick with producing only (nothing made: no pick)", ok and err.pick == nil, serpent.line(err))
    remote.call("srq", "set", F, "producing_only", false)
  end,
  function()
    -- research a burst of techs by script: no crash, no announce spam
    local n = 0
    for _, t in pairs(game.forces[F].technologies) do
      if startable(t) and n < 10 then
        t.researched = true
        n = n + 1
      end
    end
    check("burst of finished research", true, n .. " techs")
  end,
  function()
    check("still researching after the burst", current() ~= nil, queue_str())
    -- queue a tech with unresearched prerequisites (a chain), for the move tests
    local force = game.forces[F]
    for _, t in pairs(force.technologies) do
      if not t.researched and t.enabled and #t.research_unit_ingredients > 0 and not startable(t) then
        local direct_unresearched = 0
        for _, p in pairs(t.prerequisites) do
          if not p.researched then
            direct_unresearched = direct_unresearched + 1
          end
        end
        local refused = remote.call("srq", "push", F, t.name)
        if not refused and #queue() >= 4 then
          trigger_case.chain = t.name
          break
        end
      end
    end
    check("queued a chain", trigger_case.chain ~= nil, queue_str())
  end,
  function()
    local q = queue()
    local native = game.forces[F].research_queue
    local ok = #native > 0 and native[1].name == current()
    for i = 1, #native do
      ok = ok and native[i].name == q[i].name
    end
    check("game's research queue mirrors the front of ours", ok,
      "ours " .. queue_str() .. " native " .. #native .. " first " .. tostring(native[1] and native[1].name))
    -- move the chain's goal to the front: its prerequisites must come along in front of it
    local last = q[#q]
    remote.call("srq", "move", F, last.name, last.level, q[1].name, q[1].level)
  end,
  function()
    local q = queue()
    local force = game.forces[F]
    local pos = {}
    for i, n in pairs(q) do
      pos[n.name] = pos[n.name] or i
    end
    local ok = true
    for i, n in pairs(q) do
      for _, p in pairs(force.technologies[n.name].prerequisites) do
        if pos[p.name] and pos[p.name] > i then
          ok = false
        end
      end
    end
    check("moving to the front keeps prerequisites first", ok, queue_str())
    -- and move the first entry to the back: what needs it follows
    remote.call("srq", "move", F, q[1].name, q[1].level, q[#q].name, q[#q].level)
  end,
  function()
    local q = queue()
    local force = game.forces[F]
    local pos = {}
    for i, n in pairs(q) do
      pos[n.name] = pos[n.name] or i
    end
    local ok = true
    for i, n in pairs(q) do
      for _, p in pairs(force.technologies[n.name].prerequisites) do
        if pos[p.name] and pos[p.name] > i then
          ok = false
        end
      end
    end
    check("moving to the back keeps dependents behind", ok, queue_str())
    check("research follows the new order", current() == (research_first_startable and nil or current()), current())
  end,
}

script.on_nth_tick(10, function(e)
  step = step + 1
  local f = steps[step]
  if f then
    local ok, err = pcall(f)
    if not ok then
      check("step " .. step .. " ran", false, err)
    end
  elseif step == #steps + 1 then
    helpers.write_file("srq-test.txt", table.concat(out, "\n") .. "\n")
  end
end)
