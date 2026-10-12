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
  -- (the drawer and settings stuck to the window's edges, not left where the window was before it was centred)
  local function beside(what)
    local win, d = screen.urq_window, screen.urq_window__auto
    local sc = player.display_scale
    if not (win and d and d.visible) then return what .. ": no drawer" end
    local wx, wy, dx, dy = win.location.x, win.location.y, d.location.x, d.location.y
    local ok = math.abs(dx - (wx + (1140 - 8) * sc)) <= 2 and math.abs(dy - (wy + 42 * sc)) <= 2
    local res = player.display_resolution
    local mid = math.abs((wx + (1140 + 352 - 8) * sc / 2) - res.width / 2) <= 2
    return string.format("%s: drawer beside %s, centred %s (window %d,%d drawer %d,%d)", what, tostring(ok),
      tostring(mid), wx, wy, dx, dy)
  end
  if themed and e.tick == 210 then
    helpers.write_file("srq-gui.txt", "", false)
    log("drawer: " .. tostring(screen.urq_window__auto ~= nil and screen.urq_window__auto.visible))
    log(beside("opened"))
    log("gear: " .. tostring(screen.urq_window and #screen.urq_window.children > 0))
    remote.call("srq", "settings", 1)
  elseif themed and e.tick == 215 then
    log("settings: " .. tostring(screen.urq_window__menu ~= nil) .. ", window still open: " .. tostring(screen.urq_window.visible))
    local m, win = screen.urq_window__menu, screen.urq_window
    if m then  -- (under the title bar's right end: its right edge 8 units in from the window's)
      local sc = player.display_scale
      log("settings at the right end: " .. tostring(math.abs((m.location.x + 300 * sc) - (win.location.x + (1140 - 8) * sc)) <= 2
        and m.location.y > win.location.y))
    end
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
  -- moved away, then "Reset size and place": the drawer comes along
  if themed and e.tick == 390 then
    remote.call("srq", "show", 1)
    screen.urq_window.location = { 5, 5 }
    remote.call("srq", "center", 1)
  elseif themed and e.tick == 392 then
    log(beside("centred again"))
  end
  -- the queue emptied (auto research off, so it stays empty): one row and a hint
  local empty_at = themed and 400 or 200
  if e.tick == empty_at then
    remote.call("srq", "set", player.force.name, "enabled", false)
    remote.call("srq", "clear", player.force.name)
    remote.call("srq", "show", 1, "logistics-2")
  elseif e.tick == empty_at + 5 then
    log("empty queue: " .. #remote.call("srq", "queue", player.force.name) .. " queued")
  elseif e.tick == empty_at + 10 then
    shoot("srq-gui-empty.png")
  end
  -- a theme of fse-std's own shapes (a taller title bar): the drawer and the settings fit it too
  local crt = themed and remote.interfaces["fse-std"] and remote.interfaces["fse-std"].set_theme
  if crt and e.tick == 440 then
    remote.call("fse-std", "set_theme", 1, "crt")
    remote.call("srq", "settings", 1)
  elseif crt and e.tick == 445 then
    shoot("srq-gui-settings-crt.png")
  elseif crt and e.tick == 470 then
    remote.call("srq", "settings", 1)
    remote.call("fse-std", "set_theme", 1, "vanilla")
  end
  if e.tick == (themed and 480 or 260) then
    helpers.write_file("srq-gui-done.txt", "done")
  end
end)
