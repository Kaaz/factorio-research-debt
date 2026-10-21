-- Debt per technology scales with the science tier of the technology: the highest-tier
-- science pack among its ingredients decides the factor. Red-only technologies are cheap,
-- late-game technologies expensive. Packs from other mods fall back to "number of distinct
-- packs" as the tier.
local Tiers = {}

Tiers.Balance = {
  packs = {
    ["automation-science-pack"] = 1,
    ["logistic-science-pack"] = 2,
    ["military-science-pack"] = 2,
    ["chemical-science-pack"] = 3,
    ["production-science-pack"] = 4,
    ["utility-science-pack"] = 4,
    ["space-science-pack"] = 5,
    ["metallurgic-science-pack"] = 5,
    ["electromagnetic-science-pack"] = 5,
    ["agricultural-science-pack"] = 5,
    ["cryogenic-science-pack"] = 6,
    ["promethium-science-pack"] = 7,
  },
  -- factor applied to the base step (rd-step) per tier
  factors = { 0.5, 1.0, 1.5, 2.0, 2.5, 3.0, 4.0 },
}

function Tiers.enabled()
  return settings.startup["rd-tier-scaling"].value
end

function Tiers.max_tier()
  return #Tiers.Balance.factors
end

-- proto: LuaTechnologyPrototype
function Tiers.tier_of(proto)
  local best, unknown = 0, 0
  for _, ing in pairs(proto.research_unit_ingredients) do
    local t = Tiers.Balance.packs[ing.name]
    if t then best = math.max(best, t) else unknown = unknown + 1 end
  end
  if best == 0 then
    best = math.min(Tiers.max_tier(), math.max(1, unknown))
  end
  return best
end

function Tiers.factor_for_tier(tier)
  return Tiers.Balance.factors[tier] or Tiers.Balance.factors[Tiers.max_tier()]
end

function Tiers.factor(proto)
  if not Tiers.enabled() then return 1 end
  return Tiers.factor_for_tier(Tiers.tier_of(proto))
end

-- For the GUI: list of { tier =, factor =, packs = {names present in this game} }
function Tiers.table()
  local by_tier = {}
  for name, tier in pairs(Tiers.Balance.packs) do
    if prototypes.item[name] then
      by_tier[tier] = by_tier[tier] or {}
      table.insert(by_tier[tier], name)
    end
  end
  local list = {}
  for tier = 1, Tiers.max_tier() do
    if by_tier[tier] then
      table.sort(by_tier[tier])
      list[#list + 1] = { tier = tier, factor = Tiers.factor_for_tier(tier), packs = by_tier[tier] }
    end
  end
  return list
end

return Tiers
