-- Trades: ways to convert something else the player values into debt reduction.
--   lab       : make the force's labs slower (reversible at the same rate)
--   evolution : raise enemy evolution on the player's current surface (irreversible)
--   forget    : un-research a technology nothing else depends on (handled by on_research_reversed)
local Debt = require("scripts.debt")
local Config = require("scripts.config")
local Bonus = require("scripts.bonus")

local Trades = {}

Trades.Balance = {
  lab_step = Config.Careful.step,          -- lab speed removed per careful step (the hidden rd-careful-mode tech)
  lab_max_steps = Config.Careful.max_steps,
  lab_debt = Config.Careful.debt,          -- debt cleared per step (at most what is left)
  evo_step = 0.05,     -- evolution added per trade
  evo_debt = 0.25,     -- debt removed per evolution trade
  evo_max = 0.95,      -- no trades once evolution is at or above this
}

function Trades.enabled()
  return settings.startup["rd-enable-trades"].value
end

-- Trades change things for everyone (debt, evolution, the team's technologies): admins only by default.
function Trades.allowed(player)
  return player.admin or not settings.global["rd-trades-admin-only"].value
end

local function fstate(force)
  storage.trades = storage.trades or {}
  local st = storage.trades[force.name]
  if not st then
    st = { lab_steps = 0, evo_trades = 0 }
    storage.trades[force.name] = st
  end
  -- debt actually cleared by each careful step, so undoing a step gives back exactly that
  -- (saves from 2.1.2 and older: every step cleared the full amount)
  if st.lab_cleared == nil then
    st.lab_cleared = {}
    for i = 1, st.lab_steps do st.lab_cleared[i] = Trades.Balance.lab_debt end
  end
  return st
end

function Trades.state(force)
  local st = fstate(force)
  return {
    lab_steps = st.lab_steps,
    lab_max_steps = Trades.Balance.lab_max_steps,
    lab_penalty = st.lab_steps * Trades.Balance.lab_step,
    lab_modifier = force.laboratory_speed_modifier,
    lab_cleared = st.lab_cleared,
    evo_trades = st.evo_trades,
  }
end

-- Lab speed (careful mode) -----------------------------------------------------

-- Debt the next careful step would clear: the full amount, or whatever is left.
function Trades.lab_value()
  return math.min(Trades.Balance.lab_debt, storage.debt)
end

-- Careful mode only means something for a force that researches with labs of its own.
function Trades.has_labs(force)
  if not force.research_enabled then return false end
  for _, surface in pairs(game.surfaces) do
    if surface.count_entities_filtered({ force = force, type = "lab", limit = 1 }) > 0 then return true end
  end
  return false
end

function Trades.lab_slow(force)
  local st = fstate(force)
  if st.lab_steps >= Trades.Balance.lab_max_steps then return false, "max" end
  if storage.debt <= 0 then return false, "nodebt" end
  if not Trades.has_labs(force) then return false, "nolabs" end
  local old = storage.debt
  st.lab_steps = st.lab_steps + 1
  local new = Debt.add(-Trades.Balance.lab_debt, "trade-lab", string.format("labs -%d%%", math.floor(st.lab_steps * Trades.Balance.lab_step * 100 + 0.5)), force)
  local cleared = old - new
  st.lab_cleared[st.lab_steps] = cleared
  storage.stats.trades_debt = storage.stats.trades_debt - cleared
  Bonus.sync(force)
  return true, cleared
end

function Trades.lab_restore(force)
  local st = fstate(force)
  if st.lab_steps <= 0 then return false, "none" end
  local cleared = table.remove(st.lab_cleared, st.lab_steps) or Trades.Balance.lab_debt
  st.lab_steps = st.lab_steps - 1
  storage.stats.trades_debt = storage.stats.trades_debt + cleared
  Debt.add(cleared, "trade-lab-undo", string.format("labs -%d%%", math.floor(st.lab_steps * Trades.Balance.lab_step * 100 + 0.5)), force)
  Bonus.sync(force)
  return true, cleared
end

-- Evolution ----------------------------------------------------------------

-- Only surfaces with enemy spawners: on a space platform, Aquilo or a peaceful planet raising evolution
-- costs nothing, so the trade would be free debt.
function Trades.evolution_surface_ok(surface)
  if not (surface and surface.valid) then return false end
  if surface.platform then return false end
  return surface.count_entities_filtered({ force = "enemy", type = "unit-spawner", limit = 1 }) > 0
end

function Trades.evolution_info(surface)
  local enemy = game.forces["enemy"]
  if not enemy then return nil end
  if not Trades.evolution_surface_ok(surface) then return nil end
  return enemy.get_evolution_factor(surface)
end

function Trades.evolution_trade(force, surface)
  local enemy = game.forces["enemy"]
  if not enemy then return false, "noenemy" end
  if not Trades.evolution_surface_ok(surface) then return false, "noenemies" end
  if storage.debt <= 0 then return false, "nodebt" end
  local evo = enemy.get_evolution_factor(surface)
  if evo >= Trades.Balance.evo_max then return false, "max" end
  local new = math.min(1, evo + Trades.Balance.evo_step)
  enemy.set_evolution_factor(new, surface)
  local st = fstate(force)
  st.evo_trades = st.evo_trades + 1
  local old = storage.debt
  local after = Debt.add(-Trades.Balance.evo_debt, "trade-evolution", string.format("%s %.0f%% -> %.0f%%", surface.name, evo * 100, new * 100), force)
  storage.stats.trades_debt = storage.stats.trades_debt - (old - after)
  return true, new
end

-- Forgetting ---------------------------------------------------------------

-- Researched, counting technologies with no researched successor: safe to un-research.
function Trades.forgettable(force)
  local list = {}
  for name, tech in pairs(force.technologies) do
    if tech.researched and Debt.counts(tech.prototype) then
      local free = true
      for _, succ in pairs(tech.successors) do
        if succ.researched or (succ.level > succ.prototype.level) then free = false break end
      end
      if free then list[#list + 1] = name end
    end
  end
  table.sort(list)
  return list
end

function Trades.forget(force, tech_name)
  local tech = force.technologies[tech_name]
  if not (tech and tech.researched) then return false, "notresearched" end
  if not Debt.counts(tech.prototype) then return false, "notcounting" end
  for _, succ in pairs(tech.successors) do
    if succ.researched then return false, "hasdependents" end
  end
  tech.researched = false -- raises on_research_reversed -> debt - step
  return true
end

-- A force is merged into another: its labs (and their careful mode) go away, so the debt the careful steps
-- cleared comes back. Without this, merging kept the reduction and dropped the slowdown.
function Trades.on_force_merging(source)
  local st = storage.trades and storage.trades[source.name]
  if not st then return end
  local back = 0
  for _, x in pairs(st.lab_cleared or {}) do back = back + x end
  storage.trades[source.name] = nil
  if back > 0 then
    storage.stats.trades_debt = storage.stats.trades_debt + back
    Debt.add(back, "trade-lab-merged", source.name)
  end
end

-- Undo every careful step and forget trade counters (used by /rd-reset).
function Trades.reset_all()
  storage.trades = {}
  Bonus.sync_all()
end

function Trades.register_events()
  -- on_technology_effects_reset is handled centrally in control.lua
end

return Trades
