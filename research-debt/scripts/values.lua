-- Balance table for the Archive. Everything a player might want to tune lives here.
--
-- Points: 1 point = Balance.debt_per_point debt. With the default step of 0.1 per
-- technology, one technology equals 100 points at full efficiency.
--
-- Diminishing returns: the efficiency of the N-th point ever offered is
--   1 / (1 + N / half_life)
-- so after half_life points have been offered, items are worth half as much.
local Values = {}

Values.Balance = {
  debt_per_point = 0.001,   -- debt removed per (effective) point
  half_life = 1000,         -- points offered before efficiency halves (1000 points = 10 technologies)
  quality_bonus = 0.6,      -- per quality level: normal 1.0, uncommon 1.6, rare 2.2, epic 2.8, legendary 4.0
  process_interval = 60,    -- ticks between archive sweeps
  -- archive requests
  request_bonus = 3,        -- value multiplier for the requested item
  request_points = 100,     -- target points per request (= one tech at the default step)
  request_min = 5,          -- minimum / maximum amount asked
  request_max = 500,
  request_queue_size = 3,   -- upcoming requests shown in advance
}

-- Item name -> points per item (at normal quality, full efficiency).
-- Items that do not exist in the current mod set are simply never matched.
Values.items = {
  -- intermediates (base)
  ["electronic-circuit"] = 0.02,
  ["advanced-circuit"] = 0.2,
  ["processing-unit"] = 1.0,
  ["engine-unit"] = 0.1,
  ["electric-engine-unit"] = 0.4,
  ["flying-robot-frame"] = 1.0,
  ["low-density-structure"] = 0.6,
  ["rocket-fuel"] = 0.3,
  ["battery"] = 0.15,
  ["uranium-235"] = 2.0,
  ["nuclear-fuel"] = 3.0,
  ["satellite"] = 150,
  -- end products that are expensive but otherwise not "progress" items
  ["power-armor-mk2"] = 150,
  ["fission-reactor-equipment"] = 40,
  ["spidertron"] = 400,
  -- science packs: deliberately cheap so that sacrificing science is never the best route
  ["automation-science-pack"] = 0.02,
  ["logistic-science-pack"] = 0.04,
  ["military-science-pack"] = 0.04,
  ["chemical-science-pack"] = 0.1,
  ["production-science-pack"] = 0.15,
  ["utility-science-pack"] = 0.15,
  ["space-science-pack"] = 0.2,
  -- Space Age
  ["tungsten-carbide"] = 0.1,
  ["tungsten-plate"] = 0.15,
  ["carbon-fiber"] = 0.2,
  ["superconductor"] = 0.5,
  ["supercapacitor"] = 0.5,
  ["holmium-plate"] = 0.1,
  ["lithium-plate"] = 0.3,
  ["quantum-processor"] = 5.0,
  ["fusion-power-cell"] = 5.0,
  ["bioflux"] = 0.05,
  ["biter-egg"] = 2.0,
  ["pentapod-egg"] = 2.0,
  ["railgun-ammo"] = 1.0,
  ["metallurgic-science-pack"] = 0.3,
  ["electromagnetic-science-pack"] = 0.3,
  ["agricultural-science-pack"] = 0.3,
  ["cryogenic-science-pack"] = 0.5,
  ["promethium-science-pack"] = 5.0,
}

function Values.value(item_name)
  return Values.items[item_name]
end

-- quality: quality prototype name (string) or nil
function Values.quality_multiplier(quality)
  if not quality or quality == "normal" then return 1 end
  local q = prototypes.quality and prototypes.quality[quality]
  if not q then return 1 end
  return 1 + Values.Balance.quality_bonus * q.level
end

-- Efficiency of the next point offered.
function Values.efficiency(total_offered)
  return 1 / (1 + (total_offered or 0) / Values.Balance.half_life)
end

-- Effective points when `points` are offered on top of `total_offered`
-- (exact integral of the efficiency curve).
function Values.effective_points(total_offered, points)
  local h = Values.Balance.half_life
  return h * math.log((h + total_offered + points) / (h + total_offered))
end

-- Sorted list of {name=, points=} for items that exist in this game, for the GUI.
function Values.available_items()
  local list = {}
  for name, pts in pairs(Values.items) do
    if prototypes.item[name] then list[#list + 1] = { name = name, points = pts } end
  end
  table.sort(list, function(a, b) return a.points > b.points end)
  return list
end

return Values
