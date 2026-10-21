-- Debt-free bonus: while the debt is exactly zero, every force's labs run faster.
-- The applied amount is tracked per force so it can be removed exactly and re-applied
-- after reset_technology_effects().
local Bonus = {}

Bonus.on_toggled = nil -- function(force, active) set by control.lua for chat messages

function Bonus.amount()
  return settings.global["rd-debt-free-bonus"].value
end

function Bonus.active()
  return (storage.debt or 0) <= 0 and Bonus.amount() > 0
end

local function relevant(force)
  return force.valid and force.name ~= "enemy" and force.name ~= "neutral"
end

-- Bring every force in line with the current debt and setting.
function Bonus.update()
  storage.bonus_applied = storage.bonus_applied or {}
  local want = Bonus.active() and Bonus.amount() or 0
  for _, force in pairs(game.forces) do
    if relevant(force) then
      local have = storage.bonus_applied[force.name] or 0
      if math.abs(want - have) > 1e-9 then
        force.laboratory_speed_modifier = force.laboratory_speed_modifier - have + want
        storage.bonus_applied[force.name] = want
        if Bonus.on_toggled and ((have == 0) ~= (want == 0)) then
          Bonus.on_toggled(force, want > 0)
        end
      end
    end
  end
end

-- reset_technology_effects() recomputed the modifier from technologies: add our part again.
function Bonus.reapply(force)
  local have = storage.bonus_applied and storage.bonus_applied[force.name] or 0
  if have ~= 0 then
    force.laboratory_speed_modifier = force.laboratory_speed_modifier + have
  end
end

function Bonus.applied(force)
  return storage.bonus_applied and storage.bonus_applied[force.name] or 0
end

return Bonus
