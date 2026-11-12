-- Lab speed: the debt curve (faster labs while the debt is low, slower while it is high) and careful mode.
-- Both are carried by hidden, script-levelled technologies (Config.LabTechs) with a laboratory-speed effect,
-- so the game applies and keeps the modifier itself: reset_technology_effects, save/load and other mods
-- writing the modifier cannot make the labs "forget". The script only decides the level
-- (finished levels = tech.level - 1) and puts it back when something else changed it.
local Config = require("scripts.config")

local Bonus = {}

Bonus.on_tier_changed = nil -- function(force, old_modifier, new_modifier) set by control.lua

local syncing = false -- our own level writes raise research events; ignore those

local function relevant(force)
  return force.valid and force.name ~= "enemy" and force.name ~= "neutral"
end

function Bonus.is_lab_tech(name)
  for _, t in pairs(Config.LabTechs) do
    if t.name == name then return true end
  end
  return false
end

function Bonus.current_modifier()
  return Config.lab_modifier(storage.debt or 0)
end

local function careful_steps(force)
  local st = storage.trades and storage.trades[force.name]
  return st and st.lab_steps or 0
end

-- Levels each hidden technology should have finished for this force.
local function wanted(force)
  local unit = Config.Curve.lab_unit
  local units = math.floor(Bonus.current_modifier() / unit + 0.5)
  local careful = careful_steps(force)
  -- floor: the curve penalty only takes what careful mode leaves of the maximum slowdown,
  -- so labs never stop (they must still be able to finish Knowledge Consolidation)
  local room = Config.Curve.max_slowdown - careful * Config.Careful.step
  local max_penalty = math.max(0, math.floor(room / unit + 1e-6))
  return {
    bonus = math.max(0, units),
    penalty = math.min(math.max(0, -units), max_penalty),
    careful = careful,
  }
end

local function finished(tech)
  return tech.level - 1
end

-- Curve modifier the force's technologies currently carry.
function Bonus.applied(force)
  local techs = force.technologies
  local b = techs[Config.LabTechs.bonus.name]
  local p = techs[Config.LabTechs.penalty.name]
  if not (b and p) then return 0 end
  return (finished(b) - finished(p)) * Config.Curve.lab_unit
end

-- Bring one force's hidden technologies to the wanted levels. Returns true if anything changed.
function Bonus.sync(force)
  if not relevant(force) then return false end
  local want = wanted(force)
  local changed = false
  syncing = true
  for key, t in pairs(Config.LabTechs) do
    local tech = force.technologies[t.name]
    if tech and finished(tech) ~= want[key] then
      tech.level = want[key] + 1
      changed = true
    end
    if tech and tech.enabled then tech.enabled = false end -- writing level enables it; keep it out of reach
  end
  syncing = false
  return changed
end

-- Bring every force in line with the current debt, careful steps and settings.
function Bonus.update()
  for _, force in pairs(game.forces) do
    if relevant(force) then
      local have = Bonus.applied(force)
      Bonus.sync(force)
      local now = Bonus.applied(force)
      if math.abs(now - have) > 1e-9 and Bonus.on_tier_changed then Bonus.on_tier_changed(force, have, now) end
    end
  end
end

-- Silent repair for every force (periodic watchdog, force reset, a hidden tech changed by someone else).
function Bonus.sync_all()
  for _, force in pairs(game.forces) do Bonus.sync(force) end
end

-- A research event for one of the hidden technologies. Never write the level from inside this event:
-- the game raises it once per level while it is still applying someone else's level write, and writing
-- back from here ping-pongs forever (seen in tests: the server hangs). The watchdog puts it back instead.
function Bonus.on_research_event(tech) -- luacheck: ignore tech
end

-- Saves from 2.1.2 and older added the curve and the careful penalty straight to laboratory_speed_modifier.
-- reset_technology_effects() recomputes the modifier from technologies, which drops those script additions
-- (whether or not they were still intact); the hidden technologies then carry them.
function Bonus.migrate_from_script_modifier()
  if storage.bonus_applied == nil then return end
  for _, force in pairs(game.forces) do
    if relevant(force) then force.reset_technology_effects() end
  end
  storage.bonus_applied = nil
  log("[research-debt] lab speed moved from script modifiers to hidden technologies")
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
