-- Trades: ways to convert something else the player values into debt reduction.
--   lab       : make the force's labs slower (reversible at the same rate)
--   evolution : raise enemy evolution on the player's current surface (irreversible)
--   forget    : un-research a technology nothing else depends on (handled by on_research_reversed)
local Debt = require("scripts.debt")

local Trades = {}

Trades.Balance = {
  lab_step = 0.10,     -- lab speed removed per trade (10%)
  lab_max_steps = 5,   -- at most 50% slower
  lab_debt = 0.25,     -- debt removed per lab step (= 2.5 technologies at the default step)
  evo_step = 0.05,     -- evolution added per trade
  evo_debt = 0.25,     -- debt removed per evolution trade
  evo_max = 0.95,      -- no trades once evolution is at or above this
}

function Trades.enabled()
  return settings.startup["rd-enable-trades"].value
end

local function fstate(force)
  storage.trades = storage.trades or {}
  local st = storage.trades[force.name]
  if not st then
    st = { lab_steps = 0, evo_trades = 0 }
    storage.trades[force.name] = st
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
    evo_trades = st.evo_trades,
  }
end

-- Lab speed ----------------------------------------------------------------

function Trades.lab_slow(force)
  local st = fstate(force)
  if st.lab_steps >= Trades.Balance.lab_max_steps then return false, "max" end
  if storage.debt <= 0 then return false, "nodebt" end
  st.lab_steps = st.lab_steps + 1
  force.laboratory_speed_modifier = force.laboratory_speed_modifier - Trades.Balance.lab_step
  storage.stats.trades_debt = storage.stats.trades_debt - Trades.Balance.lab_debt
  Debt.add(-Trades.Balance.lab_debt, "trade-lab", string.format("labs -%d%%", math.floor(st.lab_steps * Trades.Balance.lab_step * 100 + 0.5)), force)
  return true
end

function Trades.lab_restore(force)
  local st = fstate(force)
  if st.lab_steps <= 0 then return false, "none" end
  st.lab_steps = st.lab_steps - 1
  force.laboratory_speed_modifier = force.laboratory_speed_modifier + Trades.Balance.lab_step
  storage.stats.trades_debt = storage.stats.trades_debt + Trades.Balance.lab_debt
  Debt.add(Trades.Balance.lab_debt, "trade-lab-undo", string.format("labs -%d%%", math.floor(st.lab_steps * Trades.Balance.lab_step * 100 + 0.5)), force)
  return true
end

-- reset_technology_effects() recomputes all modifiers from technologies and wipes our penalty.
function Trades.reapply_lab_penalty(force)
  local st = storage.trades and storage.trades[force.name]
  if st and st.lab_steps > 0 then
    force.laboratory_speed_modifier = force.laboratory_speed_modifier - st.lab_steps * Trades.Balance.lab_step
  end
end

-- Evolution ----------------------------------------------------------------

function Trades.evolution_info(surface)
  local enemy = game.forces["enemy"]
  if not enemy then return nil end
  return enemy.get_evolution_factor(surface)
end

function Trades.evolution_trade(force, surface)
  local enemy = game.forces["enemy"]
  if not enemy then return false, "noenemy" end
  if storage.debt <= 0 then return false, "nodebt" end
  local evo = enemy.get_evolution_factor(surface)
  if evo >= Trades.Balance.evo_max then return false, "max" end
  local new = math.min(1, evo + Trades.Balance.evo_step)
  enemy.set_evolution_factor(new, surface)
  local st = fstate(force)
  st.evo_trades = st.evo_trades + 1
  storage.stats.trades_debt = storage.stats.trades_debt - Trades.Balance.evo_debt
  Debt.add(-Trades.Balance.evo_debt, "trade-evolution", string.format("%s %.0f%% -> %.0f%%", surface.name, evo * 100, new * 100), force)
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

-- Undo every lab penalty and forget trade counters (used by /rd-reset).
function Trades.reset_all()
  for name, st in pairs(storage.trades or {}) do
    local force = game.forces[name]
    if force and force.valid and st.lab_steps > 0 then
      force.laboratory_speed_modifier = force.laboratory_speed_modifier + st.lab_steps * Trades.Balance.lab_step
    end
  end
  storage.trades = {}
end

function Trades.register_events()
  -- on_technology_effects_reset is handled centrally in control.lua
end

return Trades
