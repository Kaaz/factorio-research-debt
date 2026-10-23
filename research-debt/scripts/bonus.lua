-- Lab speed curve: faster labs while the debt is low, slower labs while it is high.
-- An additive force modifier tracked per force so it can be removed exactly and re-applied
-- after reset_technology_effects(). (The lab productivity per Knowledge Consolidation level is a
-- native technology effect, applied by the game itself.)
local Config = require("scripts.config")

local Bonus = {}

Bonus.on_tier_changed = nil -- function(force, old_modifier, new_modifier) set by control.lua

local function relevant(force)
  return force.valid and force.name ~= "enemy" and force.name ~= "neutral"
end

function Bonus.current_modifier()
  return Config.lab_modifier(storage.debt or 0)
end

-- Bring every force's lab speed in line with the current debt and settings.
function Bonus.update()
  storage.bonus_applied = storage.bonus_applied or {}
  local want = Bonus.current_modifier()
  for _, force in pairs(game.forces) do
    if relevant(force) then
      local have = storage.bonus_applied[force.name] or 0
      if math.abs(want - have) > 1e-9 then
        force.laboratory_speed_modifier = force.laboratory_speed_modifier - have + want
        storage.bonus_applied[force.name] = want
        if Bonus.on_tier_changed then Bonus.on_tier_changed(force, have, want) end
      end
    end
  end
end

-- reset_technology_effects() recomputed the modifiers from technologies: add ours again.
function Bonus.reapply(force)
  local have = storage.bonus_applied and storage.bonus_applied[force.name] or 0
  if have ~= 0 then
    force.laboratory_speed_modifier = force.laboratory_speed_modifier + have
  end
end

function Bonus.applied(force)
  return storage.bonus_applied and storage.bonus_applied[force.name] or 0
end

-- For the GUI: current step of the curve and the nearest better / worse steps.
function Bonus.describe(debt)
  local rows = Config.lab_curve()
  for i, r in ipairs(rows) do
    local above_from = (r.from == nil) or (debt > r.from + 1e-9)
    local below_to = (r.to == nil) or (debt <= r.to + 1e-9)
    if above_from and below_to then
      return r, rows[i - 1], rows[i + 1]
    end
  end
  return rows[#rows], rows[#rows - 1], nil
end

return Bonus
