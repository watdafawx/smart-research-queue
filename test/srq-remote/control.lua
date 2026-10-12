-- (run_remote.py) what the test needs that no interface has
remote.add_interface("srq-remote-test", {
  -- trigger technologies (crafting, mining, ...) done, so there is something labs can research
  prepare = function(force_name)
    local force = game.forces[force_name]
    for _ = 1, 20 do
      local changed = false
      for _, t in pairs(force.technologies) do
        if not t.researched and t.enabled and t.prototype.research_trigger then
          local ready = true
          for _, p in pairs(t.prerequisites) do
            if not p.researched then ready = false end
          end
          if ready then
            t.researched = true
            changed = true
          end
        end
      end
      if not changed then break end
    end
    remote.call("srq", "set", force_name, "enabled", true)
  end,
  -- the current research finished by script
  finish = function(force_name)
    local r = game.forces[force_name].current_research
    if not r then return nil end
    r.researched = true
    return r.name
  end,
})
