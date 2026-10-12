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
  -- with fse-std (run_gui.py --themed): the settings behind the gear, Auto Research as a drawer, inside again, the
  -- queue's Clear asking first
  local themed = script.active_mods["fse-std"] ~= nil
  local screen = player.gui.screen
  local function log(t) helpers.write_file("srq-gui.txt", t .. "\n", true) end
  local function shoot(file) game.take_screenshot({ player = player, show_gui = true, path = file, resolution = { 2560, 1440 }, zoom = 1 }) end
  if themed and e.tick == 210 then
    helpers.write_file("srq-gui.txt", "", false)
    log("drawer: " .. tostring(screen.urq_window__auto ~= nil and screen.urq_window__auto.visible))
    log("gear: " .. tostring(screen.urq_window and #screen.urq_window.children > 0))
    remote.call("srq", "settings", 1)
  elseif themed and e.tick == 215 then
    log("settings: " .. tostring(screen.urq_window__menu ~= nil) .. ", window still open: " .. tostring(screen.urq_window.visible))
  elseif themed and e.tick == 230 then
    shoot("srq-gui-settings.png")
  elseif themed and e.tick == 260 then
    remote.call("srq", "docked", 1, false)
  elseif themed and e.tick == 270 then
    log("inside: drawer " .. tostring(screen.urq_window__auto ~= nil) .. ", window " .. tostring(screen.urq_window.visible))
  elseif themed and e.tick == 290 then
    shoot("srq-gui-inside.png")
  elseif themed and e.tick == 320 then
    remote.call("srq", "docked", 1, true)
    remote.call("srq", "push", player.force.name, "steel-processing")
  elseif themed and e.tick == 330 then
    remote.call("srq", "press_clear", 1)
  elseif themed and e.tick == 335 then
    log("clear asks: " .. tostring(screen["fstd_confirm_srq_clear"] ~= nil) .. ", queue kept: "
      .. tostring(#remote.call("srq", "queue", player.force.name) > 0) .. ", window still open: " .. tostring(screen.urq_window.visible))
  elseif themed and e.tick == 355 then
    shoot("srq-gui-clear.png")
  elseif themed and e.tick == 380 then
    remote.call("srq", "hide", 1)
  elseif themed and e.tick == 385 then
    log("hidden: drawer hidden " .. tostring(not (screen.urq_window__auto and screen.urq_window__auto.visible)))
  end
  if e.tick == (themed and 400 or 260) then
    helpers.write_file("srq-gui-done.txt", "done")
  end
end)
