-- Core model: one number, storage.debt (>= 0). The multiplier is derived from it.
-- apply_multiplier() is the ONLY place that writes technology_price_multiplier.
local Tiers = require("scripts.tiers")
local Config = require("scripts.config")

local Debt = {}

Debt.HARD_MIN = 0.001
Debt.HARD_MAX = 100000
Debt.HISTORY_SIZE = 30
Debt.INFINITE_LEVEL = 4294967295 -- LuaTechnologyPrototype.max_level for max_level = "infinite"
Debt.CONSOLIDATION_TECH = "rd-consolidation-1"

-- Callbacks other modules can hook (set by control.lua).
Debt.on_changed = nil -- function(info) called after every debt/multiplier change

local function new_stats()
  return {
    techs_counted = 0, techs_debt = 0,
    reversed = 0, reversed_debt = 0,
    consolidation_levels = 0, consolidation_debt = 0,
    archive_items = 0, archive_debt = 0, archive_points = 0,
    trades_debt = 0,
    requests_completed = 0, requests_expired = 0,
    other_debt = 0,
  }
end

function Debt.init_storage()
  storage.debt = storage.debt or 0
  if storage.base_multiplier == nil then
    storage.base_multiplier = game.difficulty_settings.technology_price_multiplier
    if math.abs(storage.base_multiplier - 1) > 1e-9 then
      log(string.format("[research-debt] WARNING: map technology_price_multiplier is %.4f (not 1). "
        .. "Using it as base. Stacking with other research-cost mods is not supported.", storage.base_multiplier))
    end
  end
  storage.stats = storage.stats or new_stats()
  for k, v in pairs(new_stats()) do
    if storage.stats[k] == nil then storage.stats[k] = v end
  end
  storage.history = storage.history or {}
  storage.archives = storage.archives or {}
  storage.total_offered = storage.total_offered or 0
  storage.trades = storage.trades or {}
  storage.gui = storage.gui or {}
end

function Debt.step()
  return Config.step()
end

-- Debt added by one level of this technology (base step × science-tier factor).
function Debt.step_for(proto)
  return Debt.step() * Tiers.factor(proto)
end

function Debt.growth_mode()
  return settings.startup["rd-growth-mode"].value
end

-- Debt the next Knowledge Consolidation level would remove (percentage of the current debt, with a floor).
function Debt.consolidation_value(debt)
  return Config.consolidation_value(debt or storage.debt or 0)
end

-- f(debt): how much more expensive research is relative to base.
function Debt.factor(debt)
  if debt < 0 then debt = 0 end
  if Debt.growth_mode() == "exponential" then
    local step = Debt.step()
    if step <= 0 then return 1 end
    -- each counted technology multiplies the cost by (1 + step)
    return (1 + step) ^ (debt / step)
  end
  return 1 + debt
end

function Debt.limits()
  local base = storage.base_multiplier or 1
  local min = math.max(Debt.HARD_MIN, base * settings.global["rd-min-multiplier"].value)
  local max = math.min(Debt.HARD_MAX, Config.max_multiplier())
  if max < min then max = min end
  return min, max
end

-- Returns clamped multiplier and the unclamped ("raw") one.
function Debt.compute_multiplier(debt)
  local base = storage.base_multiplier or 1
  local raw = base * Debt.factor(debt)
  local min, max = Debt.limits()
  local m = raw
  if m < min then m = min end
  if m > max then m = max end
  return m, raw
end

function Debt.apply_multiplier()
  local m, raw = Debt.compute_multiplier(storage.debt)
  game.difficulty_settings.technology_price_multiplier = m
  storage.current_multiplier = m
  storage.raw_multiplier = raw
  return m
end

local function push_history(entry)
  local h = storage.history
  h[#h + 1] = entry
  while #h > Debt.HISTORY_SIZE do table.remove(h, 1) end
end

-- The single entry point for changing debt. reason: "research", "reversed",
-- "consolidation", "archive", "recalc", "script", "reset". detail: free text (tech name, item...).
-- Logs every change; the log line doubles as a test interface.
function Debt.add(delta, reason, detail, force)
  local old = storage.debt
  local new = old + delta
  if new < 0 then new = 0 end
  -- avoid float dust
  new = math.floor(new * 1e9 + 0.5) / 1e9
  local applied = new - old
  storage.debt = new
  local old_m = storage.current_multiplier or storage.base_multiplier
  local m = Debt.apply_multiplier()
  log(string.format("[research-debt] debt %.4f -> %.4f (%+.4f) reason=%s detail=%s | multiplier %.4f -> %.4f",
    old, new, applied, reason, tostring(detail), old_m, m))
  push_history({
    tick = game.tick, delta = applied, reason = reason, detail = detail,
    debt = new, multiplier = m, force = force and force.name or nil,
  })
  if Debt.on_changed then
    Debt.on_changed({ delta = applied, reason = reason, detail = detail, old_multiplier = old_m, multiplier = m, force = force })
  end
  return new, m
end

-- Classification -----------------------------------------------------------

function Debt.is_infinite(proto)
  return proto.max_level == Debt.INFINITE_LEVEL
end

function Debt.is_own_tech(proto)
  return proto.name:sub(1, 3) == "rd-"
end

-- Does researching this technology (one level of it) add debt?
function Debt.counts(proto)
  if Debt.is_own_tech(proto) then return false end
  if Debt.is_infinite(proto) then return false end
  if proto.research_trigger ~= nil and not settings.startup["rd-count-trigger-techs"].value then
    return false
  end
  return true
end

-- Count every researched, counting technology of every force. Used when the mod is
-- added to an existing save (on_configuration_changed) and for /rd-recalc.
function Debt.count_researched()
  local n, total = 0, 0
  local per_force = {}
  for _, force in pairs(game.forces) do
    local fn = 0
    for _, tech in pairs(force.technologies) do
      if tech.researched and Debt.counts(tech.prototype) then
        fn = fn + 1
        total = total + Debt.step_for(tech.prototype)
      end
    end
    if fn > 0 then per_force[force.name] = fn end
    n = n + fn
  end
  return n, per_force, total
end

function Debt.recalculate(reason)
  local n, per_force, target = Debt.count_researched()
  -- Keep reductions already earned (consolidation/archive), only re-derive the research part.
  local st = storage.stats
  local reductions = st.consolidation_debt + st.archive_debt + st.trades_debt -- all negative numbers
  local new = math.max(0, target + reductions)
  st.techs_counted = n
  st.techs_debt = target
  st.reversed = 0
  st.reversed_debt = 0
  storage.debt = 0
  Debt.add(new, reason or "recalc", string.format("%d researched technologies", n))
  return n, per_force
end

function Debt.reset()
  storage.debt = 0
  storage.stats = new_stats()
  storage.history = {}
  storage.total_offered = 0
  Debt.add(0, "reset", nil)
end

-- Snapshot for /rd-status, the remote interface and tests.
function Debt.status()
  local m, raw = Debt.compute_multiplier(storage.debt)
  local min, max = Debt.limits()
  return {
    debt = storage.debt,
    base_multiplier = storage.base_multiplier,
    multiplier = m,
    raw_multiplier = raw,
    actual_multiplier = game.difficulty_settings.technology_price_multiplier,
    factor = Debt.factor(storage.debt),
    min_multiplier = min,
    max_multiplier = max,
    step = Debt.step(),
    growth_mode = Debt.growth_mode(),
    consolidation_value = Debt.consolidation_value(),
    consolidation_percent = Config.consolidation_percent(),
    consolidation_min = Config.consolidation_min(),
    stats = storage.stats,
    total_offered = storage.total_offered,
    archives = table_size(storage.archives),
    history_size = #storage.history,
  }
end

return Debt
