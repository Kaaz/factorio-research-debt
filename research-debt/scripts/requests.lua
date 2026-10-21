-- Archive requests: periodically the Archive asks for a specific item at a bonus value.
-- One global request at a time (debt is global too). Items delivered to any Archive count.
local Values = require("scripts.values")

local Requests = {}

Requests.on_new = nil  -- function(request) set by control.lua (chat message)
Requests.on_done = nil -- function(request)

local function interval_ticks()
  return settings.global["rd-request-interval"].value * 60 * 60
end

function Requests.enabled()
  return settings.global["rd-request-interval"].value > 0 and prototypes.entity["rd-archive"] ~= nil
end

-- item -> true when some force with research can currently craft it
local function producible_items()
  local can = {}
  local forces = {}
  for _, force in pairs(game.forces) do
    if force.name ~= "enemy" and force.name ~= "neutral" and force.research_enabled then
      forces[#forces + 1] = force
    end
  end
  for name, recipe in pairs(prototypes.recipe) do
    for _, product in pairs(recipe.products) do
      if product.type == "item" and Values.items[product.name] and not can[product.name] then
        for _, force in pairs(forces) do
          local r = force.recipes[name]
          if r and r.enabled then
            can[product.name] = true
            break
          end
        end
      end
    end
  end
  return can
end

function Requests.candidates()
  local can = producible_items()
  local list = {}
  for name, pts in pairs(Values.items) do
    if can[name] and prototypes.item[name] then list[#list + 1] = name end
  end
  table.sort(list)
  return list
end

local function default_amount(item)
  local B = Values.Balance
  local value = Values.value(item) or 1
  local amount = math.ceil(B.request_points / value)
  return math.max(B.request_min, math.min(B.request_max, amount))
end

-- Pick a random craftable item, preferring one not already current or queued.
local function draw_item(list)
  local taken = {}
  if storage.request then taken[storage.request.item] = true end
  for _, q in pairs(storage.request_queue or {}) do taken[q.item] = true end
  local free = {}
  for _, name in ipairs(list) do if not taken[name] then free[#free + 1] = name end end
  if #free > 0 then return free[math.random(#free)] end
  return list[math.random(#list)]
end

-- Keep `request_queue_size` upcoming requests ready so players can plan ahead.
function Requests.fill_queue()
  storage.request_queue = storage.request_queue or {}
  local target = Values.Balance.request_queue_size
  if #storage.request_queue >= target then return end
  local list = Requests.candidates()
  if #list == 0 then return end
  while #storage.request_queue < target do
    local item = draw_item(list)
    storage.request_queue[#storage.request_queue + 1] = { item = item, amount = default_amount(item) }
  end
end

function Requests.upcoming()
  return storage.request_queue or {}
end

-- Creates a request for `item` (tests), or promotes the head of the queue. Queued items
-- that can no longer be crafted (a technology was forgotten) are skipped.
-- Returns the request or nil when nothing is producible.
function Requests.new(item, amount)
  if not item then
    local can = {}
    for _, name in ipairs(Requests.candidates()) do can[name] = true end
    storage.request_queue = storage.request_queue or {}
    while #storage.request_queue > 0 and not item do
      local head = table.remove(storage.request_queue, 1)
      if can[head.item] then item, amount = head.item, head.amount end
    end
    if not item then
      Requests.fill_queue()
      local head = table.remove(storage.request_queue or {}, 1)
      if head then item, amount = head.item, head.amount end
    end
    if not item then
      -- nothing craftable yet (early game): look again in a minute instead of a full interval
      storage.request = nil
      storage.next_request_tick = game.tick + 60 * 60
      return nil
    end
  end
  amount = amount or default_amount(item)
  local req = {
    item = item, amount = amount, delivered = 0, bonus = Values.Balance.request_bonus,
    started_tick = game.tick, expires_tick = game.tick + interval_ticks(),
  }
  storage.request = req
  storage.last_request_item = item
  storage.next_request_tick = req.expires_tick
  Requests.fill_queue()
  if Requests.on_new then Requests.on_new(req) end
  return req
end

function Requests.current()
  return storage.request
end

-- Called by the archive when `count` items named `name` are consumed. Returns the
-- number of those items that get the bonus value.
function Requests.deliver(name, count)
  local req = storage.request
  if not req or req.item ~= name or req.delivered >= req.amount then return 0 end
  local n = math.min(count, req.amount - req.delivered)
  req.delivered = req.delivered + n
  if req.delivered >= req.amount then
    storage.stats.requests_completed = (storage.stats.requests_completed or 0) + 1
    storage.request = nil
    storage.next_request_tick = game.tick + interval_ticks()
    if Requests.on_done then Requests.on_done(req) end
  end
  return n
end

-- Periodic: draw a new request when due or expired.
function Requests.tick()
  if not Requests.enabled() then return end
  local req = storage.request
  if req and game.tick >= req.expires_tick then
    storage.stats.requests_expired = (storage.stats.requests_expired or 0) + 1
    storage.request = nil
    storage.next_request_tick = game.tick
  end
  if not storage.request and (not storage.next_request_tick or game.tick >= storage.next_request_tick) then
    Requests.new()
  end
  Requests.fill_queue()
end

function Requests.reset()
  storage.request = nil
  storage.request_queue = {}
  storage.next_request_tick = nil
end

return Requests
