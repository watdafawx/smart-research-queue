-- Drag to reorder the queue: with the fnative loader's std plugin, through the fnative-std library mod (an optional
-- dependency). Without them nothing here does anything, and the queue keeps its own way: Ctrl + click picks a
-- technology up, a click on another drops it there.

local M = {}
local has_std = script.active_mods["fnative-std"] ~= nil
local dnd, input
if has_std then
  dnd = require("__fnative-std__/dnd")
  input = require("__fnative-std__/input")
end

function M.active()
  return has_std and input.native()
end

--- a queue button: dragged by its key, dropped on another queue button
function M.mark(button, key)
  if M.active() then
    dnd.draggable(button, { kind = "srq", key = key })
    dnd.droppable(button, "srq")
  end
end

--- the click was the end of a drag (dnd used it): ignore it
function M.handled(e)
  return has_std and dnd.handled(e)
end

--- on_drop(player, payload, target): after every other registration (it chains onto the handlers already there)
function M.register(on_drop)
  if not has_std then return end
  dnd.on_drop(on_drop)
  for _, t in ipairs({ input.handlers, dnd.handlers }) do
    for ev, fn in pairs(t) do
      local prev = script.get_event_handler(ev)
      script.on_event(ev, function(e)
        if prev then prev(e) end
        local ok, err = pcall(fn, e)
        if not ok then log("[smart-research-queue] drag: " .. tostring(err)) end
      end)
    end
  end
end

--- (tests: hover events can't be faked, so a test names the element under the "mouse")
function M.test_hover(player_index, element)
  if has_std then input.hovered[player_index] = element end
end

return M
