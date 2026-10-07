-- Opens the queue window in a real client on a few technologies and screenshots each (script-output/srq-gui-*.png)
local shots = {
  { tick = 60, tech = "space-platform", file = "srq-gui-1.png" }, -- unlocks space platforms: crashed URQ 2.0.9
  { tick = 120, tech = "automation-science-pack", file = "srq-gui-2.png" }, -- trigger technology
  { tick = 180, tech = "logistics-2", file = "srq-gui-3.png" },
}

local function setup(force)
  -- some research done so the auto panel has choices; a goal and a blacklist entry
  for _ = 1, 5 do
    for _, t in pairs(force.technologies) do
      if not t.researched and t.prototype.research_trigger then
        local ready = true
        for _, p in pairs(t.prerequisites) do
          ready = ready and p.researched
        end
        if ready then
          t.researched = true
        end
      end
    end
  end
  remote.call("srq", "add", force.name, "goals", "logistic-science-pack")
  remote.call("srq", "add", force.name, "goals", "fast-inserter")
  remote.call("srq", "add", force.name, "blacklist", "stone-wall")
  remote.call("srq", "push", force.name, "steel-processing")
end

script.on_event(defines.events.on_tick, function(e)
  local player = game.get_player(1)
  if not player then
    return
  end
  if e.tick == 30 then
    setup(player.force)
  end
  for _, shot in pairs(shots) do
    if e.tick == shot.tick then
      remote.call("srq", "show", 1, shot.tech)
    elseif e.tick == shot.tick + 20 then
      game.take_screenshot({ player = player, show_gui = true, path = shot.file, resolution = { 2560, 1440 }, zoom = 1 })
    end
  end
  if e.tick == 260 then
    helpers.write_file("srq-gui-done.txt", "done")
  end
end)
