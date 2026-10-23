-- Presets and resolved configuration. With a preset other than "custom" the individual
-- settings are ignored and the preset table wins. Usable in the data stage and at runtime
-- (only `settings.startup` is touched in the data stage).
local Config = {}

Config.Presets = {
  relaxed = {
    step = 0.05, tier_scaling = true, consolidation_min = 0.35,
    consolidation_percents = { 0.15, 0.20, 0.25, 0.30 }, consolidation_bases = { 400, 800, 1600, 3200 },
    consolidation_growth = 1.15, consolidation_time = 45,
    archive_half_life = 2000, request_interval = 10,
    bonus_peak = 0.20, penalty_threshold = nil, penalty = 0,
    max_multiplier = 10,
  },
  standard = {
    step = 0.10, tier_scaling = true, consolidation_min = 0.25,
    consolidation_percents = { 0.10, 0.15, 0.20, 0.25 }, consolidation_bases = { 500, 1000, 2000, 4000 },
    consolidation_growth = 1.2, consolidation_time = 45,
    archive_half_life = 1000, request_interval = 15,
    bonus_peak = 0.20, penalty_threshold = 3.0, penalty = 0.10,
    max_multiplier = 50,
  },
  hardcore = {
    step = 0.15, tier_scaling = true, consolidation_min = 0.20,
    consolidation_percents = { 0.08, 0.12, 0.16, 0.20 }, consolidation_bases = { 750, 1500, 3000, 6000 },
    consolidation_growth = 1.25, consolidation_time = 45,
    archive_half_life = 500, request_interval = 20,
    bonus_peak = 0.10, penalty_threshold = 2.5, penalty = 0.15,
    max_multiplier = 100,
  },
}

-- Shape of the lab speed curve (fractions of bonus_peak below, multiples of penalty above).
Config.Curve = {
  bonus_steps = { { max_debt = 0.0, factor = 1.0 }, { max_debt = 0.5, factor = 0.5 }, { max_debt = 1.0, factor = 0.25 } },
  penalty_steps = { { from_threshold = 0, factor = 1 }, { from_threshold = 2.0, factor = 2 } }, -- threshold, threshold + 2
  milestone_levels = 5,     -- Knowledge Consolidation levels per milestone
  milestone_bonus = 0.02,   -- laboratory productivity per milestone
}

function Config.preset_name()
  local s = settings.startup["rd-preset"]
  return s and s.value or "standard"
end

function Config.preset()
  return Config.Presets[Config.preset_name()] -- nil for "custom"
end

local function pick(preset_key, setting_scope, setting_name, fallback)
  local p = Config.preset()
  if p then return p[preset_key] end
  local tbl = setting_scope == "startup" and settings.startup or settings.global
  local s = tbl[setting_name]
  if s == nil then return fallback end
  return s.value
end

-- startup-stage values
function Config.step() return pick("step", "startup", "rd-step", 0.1) end
function Config.tier_scaling() return pick("tier_scaling", "startup", "rd-tier-scaling", true) end
function Config.consolidation_min() return pick("consolidation_min", "startup", "rd-consolidation-value", 0.25) end

-- Custom preset: the percent setting is tier II; the other tiers scale with the standard ratios.
local CUSTOM_PERCENT_SCALE = { 2 / 3, 1, 4 / 3, 5 / 3 }
local CUSTOM_BASES = { 500, 1000, 2000, 4000 }

function Config.consolidation_percent(tier)
  tier = tier or 1
  local p = Config.preset()
  if p then return p.consolidation_percents[tier] or p.consolidation_percents[#p.consolidation_percents] end
  return settings.startup["rd-consolidation-percent"].value * (CUSTOM_PERCENT_SCALE[tier] or 1)
end
function Config.consolidation_growth()
  local p = Config.preset()
  return p and p.consolidation_growth or 1.2
end
function Config.consolidation_base(tier)
  local p = Config.preset()
  local bases = p and p.consolidation_bases or CUSTOM_BASES
  return bases[tier] or bases[#bases]
end
function Config.consolidation_formula(tier)
  return string.format("%d*%s^(L-1)", Config.consolidation_base(tier or 1), tostring(Config.consolidation_growth()))  -- e.g. 500*1.2^(L-1)
end
function Config.consolidation_time()
  local p = Config.preset()
  return p and p.consolidation_time or 45
end
-- Debt removed by the next Knowledge Consolidation level of `tier` at a given debt.
function Config.consolidation_value(debt, tier)
  return math.max(Config.consolidation_min(), Config.consolidation_percent(tier or 1) * (debt or 0))
end
function Config.archive_half_life()
  local p = Config.preset()
  return p and p.archive_half_life or 1000
end

-- runtime-global values
function Config.request_interval() return pick("request_interval", "global", "rd-request-interval", 15) end
function Config.bonus_peak() return pick("bonus_peak", "global", "rd-debt-free-bonus", 0.2) end
function Config.max_multiplier() return pick("max_multiplier", "global", "rd-max-multiplier", 50) end
function Config.penalty_threshold()
  local p = Config.preset()
  if p then return p.penalty_threshold end
  local t = settings.global["rd-penalty-threshold"].value
  if t <= 0 then return nil end
  return t
end
function Config.penalty()
  local p = Config.preset()
  if p then return p.penalty end
  return settings.global["rd-penalty"].value
end

-- Lab speed modifier for a debt value: bonus below 1.0, nothing in between, penalty above the threshold.
function Config.lab_modifier(debt)
  local peak = Config.bonus_peak()
  for _, s in ipairs(Config.Curve.bonus_steps) do
    if debt <= s.max_debt + 1e-9 then return peak * s.factor end
  end
  local th, pen = Config.penalty_threshold(), Config.penalty()
  if th and pen > 0 then
    local mod = 0
    for _, s in ipairs(Config.Curve.penalty_steps) do
      if debt >= th + s.from_threshold then mod = -pen * s.factor end
    end
    return mod
  end
  return 0
end

-- The whole curve as a list of { debt_from, debt_to, modifier } for the GUI (to = nil means open ended).
function Config.lab_curve()
  local peak, rows = Config.bonus_peak(), {}
  local prev = nil
  for _, s in ipairs(Config.Curve.bonus_steps) do
    rows[#rows + 1] = { from = prev, to = s.max_debt, modifier = peak * s.factor }
    prev = s.max_debt
  end
  local th, pen = Config.penalty_threshold(), Config.penalty()
  if th and pen > 0 then
    rows[#rows + 1] = { from = prev, to = th, modifier = 0 }
    local steps = Config.Curve.penalty_steps
    for i, s in ipairs(steps) do
      local nxt = steps[i + 1]
      rows[#rows + 1] = { from = th + s.from_threshold, to = nxt and (th + nxt.from_threshold) or nil, modifier = -pen * s.factor }
    end
  else
    rows[#rows + 1] = { from = prev, to = nil, modifier = 0 }
  end
  return rows
end

-- Snapshot for the GUI, /rd-status and tests.
function Config.resolved()
  return {
    preset = Config.preset_name(),
    step = Config.step(), tier_scaling = Config.tier_scaling(),
    consolidation_percents = { Config.consolidation_percent(1), Config.consolidation_percent(2), Config.consolidation_percent(3), Config.consolidation_percent(4) },
    consolidation_bases = { Config.consolidation_base(1), Config.consolidation_base(2), Config.consolidation_base(3), Config.consolidation_base(4) },
    consolidation_min = Config.consolidation_min(), consolidation_growth = Config.consolidation_growth(),
    consolidation_time = Config.consolidation_time(),
    archive_half_life = Config.archive_half_life(), request_interval = Config.request_interval(),
    bonus_peak = Config.bonus_peak(), penalty_threshold = Config.penalty_threshold(), penalty = Config.penalty(),
    max_multiplier = Config.max_multiplier(),
    milestone_levels = Config.Curve.milestone_levels, milestone_bonus = Config.Curve.milestone_bonus,
  }
end

return Config
