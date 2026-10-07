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
    local tech = button.tags and button.tags.tech_name
    dnd.draggable(button, { kind = "srq", key = key, sprite = tech and ("technology/" .. tech) or nil, card_size = 68, preview = true })
    dnd.droppable(button, "srq")
  end
end

--- the click was the end of a drag (dnd used it): ignore it
function M.handled(e)
  return has_std and dnd.handled(e)
end

local hidden = {}  -- player_index -> indexes of the source slot's children hidden while it is dragged

--- the card slides: the dragged slot takes the place of the one under the cursor, the others shift along
local function slide(source, target)
  local parent = source.parent
  local a, b = source.get_index_in_parent(), target.get_index_in_parent()
  local step = a < b and 1 or -1
  for i = a, b - step, step do parent.swap_children(i, i + step) end
end

--- on_drop(player, payload, target): after every other registration (it chains onto the handlers already there)
--- reset(player): put the queue buttons back in queue order (a drag that dropped nothing)
function M.register(on_drop, reset)
  if not has_std then return end
  dnd.on_drop(on_drop)
  dnd.on_phase(function(player, phase, _, source, target, dropped)
    local valid = source and source.valid
    if phase == "start" and valid then
      -- (the dragged slot becomes an empty cell: the gap the card will land in)
      local tags = source.tags
      tags.srq_gap, tags.srq_style = true, source.style.name
      source.tags = tags
      source.style = "srq_slot_gap"
      local list = {}
      for i, child in ipairs(source.children) do
        if child.visible then
          child.visible = false
          list[#list + 1] = i
        end
      end
      hidden[player.index] = list
    elseif phase == "over" then
      if valid and target and target.valid then slide(source, target) else reset(player) end
    elseif phase == "end" then
      if valid then
        local tags = source.tags
        source.style = tags.srq_style or source.style.name
        tags.srq_gap, tags.srq_style = nil, nil
        source.tags = tags
        local children = source.children
        for _, i in ipairs(hidden[player.index] or {}) do
          if children[i] then children[i].visible = true end
        end
      end
      hidden[player.index] = nil
      if not dropped then reset(player) end
    end
  end)
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
