-- The Archive: a chest that consumes valuable items and pays off research debt.
local Debt = require("scripts.debt")
local Values = require("scripts.values")
local Requests = require("scripts.requests")

local Archive = {}
Archive.ENTITY = "rd-archive"

function Archive.enabled()
  return prototypes.entity[Archive.ENTITY] ~= nil
end

function Archive.register(entity)
  if entity and entity.valid and entity.name == Archive.ENTITY and entity.unit_number then
    storage.archives[entity.unit_number] = entity
  end
end

function Archive.unregister(entity)
  if entity and entity.unit_number then
    storage.archives[entity.unit_number] = nil
  end
end

-- Rebuild the registry from the map (used after the mod is added to an existing save).
function Archive.rescan()
  storage.archives = {}
  if not Archive.enabled() then return 0 end
  local n = 0
  for _, surface in pairs(game.surfaces) do
    for _, e in pairs(surface.find_entities_filtered({ name = Archive.ENTITY })) do
      Archive.register(e)
      n = n + 1
    end
  end
  return n
end

local function show_text(entity, text, color)
  rendering.draw_text({
    text = text,
    surface = entity.surface,
    target = { entity.position.x, entity.position.y - 1 },
    color = color,
    scale = 1.2,
    time_to_live = 150,
    forces = { entity.force },
    alignment = "center",
  })
end

-- Consume everything with a value from one archive. Returns points removed, items removed.
function Archive.process(entity)
  local inv = entity.get_inventory(defines.inventory.chest)
  if not inv or inv.is_empty() then return 0, 0 end
  local points, items = 0, 0
  for _, stack in pairs(inv.get_contents()) do
    local v = Values.value(stack.name)
    if v then
      local removed = inv.remove({ name = stack.name, count = stack.count, quality = stack.quality })
      if removed > 0 then
        local bonus_n = Requests.deliver(stack.name, removed)
        local q = Values.quality_multiplier(stack.quality)
        points = points + v * q * (removed - bonus_n) + v * q * bonus_n * Values.Balance.request_bonus
        items = items + removed
      end
    end
  end
  if points > 0 then
    local effective = Values.effective_points(storage.total_offered, points)
    storage.total_offered = storage.total_offered + points
    local delta = -effective * Values.Balance.debt_per_point
    local st = storage.stats
    st.archive_items = st.archive_items + items
    st.archive_points = st.archive_points + points
    st.archive_debt = st.archive_debt + delta
    local _, m = Debt.add(delta, "archive", string.format("%d items, %.1f points (%.1f effective)", items, points, effective), entity.force)
    show_text(entity, string.format("%+.3f debt  (x%.2f)", delta, m), { r = 0.5, g = 1, b = 0.5 })
  end
  return points, items
end

function Archive.process_all()
  for unit_number, entity in pairs(storage.archives) do
    if entity.valid then
      Archive.process(entity)
    else
      storage.archives[unit_number] = nil
    end
  end
end

-- Event wiring --------------------------------------------------------------

local filter = { { filter = "name", name = Archive.ENTITY } }

local function on_built(event)
  Archive.register(event.entity)
end

local function on_removed(event)
  Archive.unregister(event.entity)
end

function Archive.register_events()
  if not Archive.enabled() then return end
  for _, ev in pairs({
    defines.events.on_built_entity, defines.events.on_robot_built_entity,
    defines.events.script_raised_built, defines.events.script_raised_revive,
    defines.events.on_space_platform_built_entity,
  }) do
    if ev then script.on_event(ev, on_built, filter) end
  end
  script.on_event(defines.events.on_entity_cloned, function(e) Archive.register(e.destination) end, filter)
  for _, ev in pairs({
    defines.events.on_player_mined_entity, defines.events.on_robot_mined_entity,
    defines.events.on_entity_died, defines.events.script_raised_destroy,
    defines.events.on_space_platform_mined_entity,
  }) do
    if ev then script.on_event(ev, on_removed, filter) end
  end
  -- periodic processing is driven from control.lua (single on_nth_tick handler per mod)
end

return Archive
