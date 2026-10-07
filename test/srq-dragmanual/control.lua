-- sets up a queue and opens the window, then leaves the real mouse to the tester (drive it by hand / computer-use)
script.on_event(defines.events.on_tick, function(e)
  if e.tick == 30 then
    for _, t in ipairs({ "automation", "logistics", "electronics", "steel-processing" }) do remote.call("srq", "push", "player", t) end
  elseif e.tick == 40 then
    remote.call("srq", "show", 1, "automation")
  end
end)
