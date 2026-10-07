-- drags a queued technology onto another in a real client with a mocked mouse (fnative std plugin)
local out = {}
local function say(s) out[#out + 1] = s end
local function q()
  local t = {}
  for _, n in pairs(remote.call("srq", "queue", "player")) do t[#t + 1] = n.name end
  return table.concat(t, ",")
end
local function mock(t) native.call("std", "mock", helpers.table_to_json(t)) end
local function shot(name)
  local p = game.get_player(1)
  game.take_screenshot({ player = 1, show_gui = true, path = "srq-drag-" .. name .. ".png",
    resolution = { p.display_resolution.width, p.display_resolution.height }, zoom = 1 })
end
local steps = {
  [30] = function()
    for _, t in ipairs({ "automation", "logistics", "electronics", "steel-processing" }) do remote.call("srq", "push", "player", t) end
  end,
  [40] = function() remote.call("srq", "show", 1, "automation") end,
  [60] = function() say("queue before: " .. q()); mock({ left = false, x = 300, y = 300, focused = true }) end,
  [70] = function() say("hover automation: " .. tostring(remote.call("srq", "test_hover", 1, "automation"))) end,
  [72] = function() mock({ left = true }) end,
  [75] = function() remote.call("srq", "test_hover", 1, "steel-processing"); mock({ x = 500, y = 310 }) end,
  [80] = function() shot("1-dragging") end,
  [85] = function() mock({ left = false }) end,
  [92] = function() say("queue after dropping automation on steel-processing: " .. q()); shot("2-dropped") end,
  [100] = function()
    native.call("std", "mock", "")
    helpers.write_file("srq-drag-result.txt", table.concat(out, "\n") .. "\n", false)
    helpers.write_file("srq-drag-done.txt", "1", false)
  end,
}
script.on_event(defines.events.on_tick, function(e)
  if not native then
    if e.tick == 60 then helpers.write_file("srq-drag-result.txt", "no native\n", false); helpers.write_file("srq-drag-done.txt", "1", false) end
    return
  end
  local f = steps[e.tick]
  if f then f() end
end)
