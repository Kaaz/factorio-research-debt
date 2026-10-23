-- Knowledge Consolidation comes in tiers that follow the science packs. Only the highest tier a
-- force has unlocked is enabled; lower tiers are switched off so the cheap early tier cannot be
-- farmed late in the game. Levels of all tiers count together for the milestones.
local Config = require("scripts.config")

local Consolidation = {}

Consolidation.PREFIX = "rd-consolidation-"

-- Shared with data.lua: which packs and prerequisites make up each tier.
Consolidation.TIERS = {
  { name = "rd-consolidation-green",  packs = { "automation-science-pack", "logistic-science-pack" },
    prerequisites = { "logistic-science-pack" }, max_level = 8 },
  { name = "rd-consolidation-blue",   packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack" },
    prerequisites = { "chemical-science-pack" }, max_level = 10 },
  { name = "rd-consolidation-yellow", packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                                                "production-science-pack", "utility-science-pack" },
    prerequisites = { "production-science-pack", "utility-science-pack" }, max_level = 12 },
  { name = "rd-consolidation-space",  packs = { "automation-science-pack", "logistic-science-pack", "chemical-science-pack",
                                                "production-science-pack", "utility-science-pack", "space-science-pack" },
    prerequisites = { "space-science-pack" }, max_level = "infinite" },
}

function Consolidation.is(name)
  return name:sub(1, #Consolidation.PREFIX) == Consolidation.PREFIX
end

function Consolidation.tier_of(name)
  for i, t in ipairs(Consolidation.TIERS) do
    if t.name == name then return i end
  end
  return nil
end

local function tier_unlocked(force, tier)
  local tech = force.technologies[tier.name]
  if not tech then return false end
  for _, pre in pairs(tech.prerequisites) do
    if not pre.researched then return false end
  end
  return true
end

-- Highest tier whose prerequisites are researched (index), or nil.
function Consolidation.active_tier(force)
  local best = nil
  for i, t in ipairs(Consolidation.TIERS) do
    if tier_unlocked(force, t) then best = i end
  end
  return best
end

function Consolidation.active_tech(force)
  local i = Consolidation.active_tier(force)
  return i and force.technologies[Consolidation.TIERS[i].name] or nil, i
end

-- Enable only the active tier. Called after any research finishes or is reversed.
function Consolidation.update_tiers(force)
  local active = Consolidation.active_tier(force)
  for i, t in ipairs(Consolidation.TIERS) do
    local tech = force.technologies[t.name]
    if tech then
      local want = (i == active)
      if tech.enabled ~= want then
        tech.enabled = want
        tech.visible_when_disabled = false
      end
    end
  end
end

function Consolidation.update_all_forces()
  for _, force in pairs(game.forces) do
    if force.name ~= "enemy" and force.name ~= "neutral" then
      Consolidation.update_tiers(force)
    end
  end
end

-- Finished levels of one tech: a finite tech that is fully researched sits at its max level.
local function finished_levels(tech)
  if tech.researched then return tech.level end
  return math.max(0, tech.level - 1)
end

-- Finished levels over all tiers (each tier starts at level 1).
function Consolidation.levels_completed(force)
  local n = 0
  for _, t in ipairs(Consolidation.TIERS) do
    local tech = force.technologies[t.name]
    if tech then n = n + finished_levels(tech) end
  end
  return n
end

-- Debt the next level of the active tier would remove.
function Consolidation.value(force, debt)
  local _, tier = Consolidation.active_tech(force)
  return Config.consolidation_value(debt, tier or 1)
end

-- Everything the GUI needs.
function Consolidation.state(force)
  local tech, tier = Consolidation.active_tech(force)
  local next_tier = nil
  for i = (tier or 0) + 1, #Consolidation.TIERS do
    if force.technologies[Consolidation.TIERS[i].name] then next_tier = i break end
  end
  local st = {
    tier = tier, tiers = #Consolidation.TIERS, next_tier = next_tier,
    next_prerequisites = next_tier and Consolidation.TIERS[next_tier].prerequisites or nil,
    levels_completed = Consolidation.levels_completed(force),
  }
  if not tech then return st end
  local queued, researching, progress = false, false, 0
  if force.current_research and force.current_research.name == tech.name then
    researching = true
    progress = force.research_progress
  end
  for _, q in pairs(force.research_queue) do
    if q.name == tech.name then queued = true end
  end
  st.tech = tech
  st.name = tech.name
  st.exhausted = tech.researched -- finite tier fully researched: wait for the next tier
  st.max_level = Consolidation.TIERS[tier].max_level
  st.available = tech.enabled and not tech.researched
  st.queued, st.researching, st.progress = queued, researching, progress
  st.units = tech.research_unit_count
  st.ingredients = tech.research_unit_ingredients
  st.level = tech.level
  st.percent = Config.consolidation_percent(tier)
  return st
end

return Consolidation
