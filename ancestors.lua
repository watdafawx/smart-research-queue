-- Every prerequisite of a technology, all the way down, earliest first (what storage.technology_prerequisites held
-- for every technology at once: ~300k strings with a big mod pack, all of it walked by the garbage collector over
-- and over). Built when asked, from the direct prerequisites in storage.technology_info, and kept for a few
-- hundred technologies at a time.

local M = {}
local memo, count = {}, 0

--- @param name string
--- @return string[]?
function M.of(name)
  local hit = memo[name]
  if hit then return hit end
  local info = storage.technology_info and storage.technology_info[name]
  if not info then return nil end
  local list, seen = {}, {}
  for _, parent_name in ipairs(info.prereqs) do
    local parent_ancestors = M.of(parent_name)
    if parent_ancestors then
      for i = 1, #parent_ancestors do
        local a = parent_ancestors[i]
        if not seen[a] then
          seen[a] = true
          list[#list + 1] = a
        end
      end
    end
    if not seen[parent_name] then
      seen[parent_name] = true
      list[#list + 1] = parent_name
    end
  end
  if count > 400 then memo, count = {}, 0 end
  memo[name] = list
  count = count + 1
  return list
end

--- (the tech tree changed: mods or a migration)
function M.reset()
  memo, count = {}, 0
end

return M
