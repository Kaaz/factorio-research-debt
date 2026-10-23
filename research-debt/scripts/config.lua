-- Presets and resolved configuration. With a preset other than "custom" the individual
-- settings are ignored and the preset table wins. Usable in the data stage and at runtime
-- (only `settings.startup` is touched in the data stage).
local Config = {}

Config.Presets = {
  relaxed = {
    step = 0.05, tier_scaling = true, consolidation_percent = 0.20, consolidation_min = 0.35,
    consolidation_formula = "500*1.25^(L-1)", consolidation_time = 45,
    archive_half_life = 2000, request_interval = 10,
    bonus_peak = 0.20, penalty_threshold = nil, penalty = 0,
    max_multiplier = 10,
  },
  standard = {
    step = 0.10, tier_scaling = true, consolidation_percent = 0.15, consolidation_min = 0.25,
    consolidation_formula = "500*1.3^(L-1)", consolidation_time = 45,
    archive_half_life = 1000, request_interval = 15,
    bonus_peak = 0.20, penalty_threshold = 3.0, penalty = 0.10,
    max_multiplier = 50,
  },
  hardcore = {
    step = 0.15, tier_scaling = true, consolidation_percent = 0.12, consolidation_min = 0.20,
    consolidation_formula = "750*1.4^(L-1)", consolidation_time = 45,
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
function Config.consolidation_percent() return pick("consolidation_percent", "startup", "rd-consolidation-percent", 0.15) end
function Config.consolidation_formula()
  local p = Config.preset()
  return p and p.consolidation_formula or "500*1.3^(L-1)"
end
function Config.consolidation_time()
  local p = Config.preset()
  return p and p.consolidation_time or 45
end
-- Debt removed by the next Knowledge Consolidation level at a given debt.
function Config.consolidation_value(debt)
  return math.max(Config.consolidation_min(), Config.consolidation_percent() * (debt or 0))
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
    consolidation_percent = Config.consolidation_percent(), consolidation_min = Config.consolidation_min(),
    consolidation_formula = Config.consolidation_formula(), consolidation_time = Config.consolidation_time(),
    archive_half_life = Config.archive_half_life(), request_interval = Config.request_interval(),
    bonus_peak = Config.bonus_peak(), penalty_threshold = Config.penalty_threshold(), penalty = Config.penalty(),
    max_multiplier = Config.max_multiplier(),
    milestone_levels = Config.Curve.milestone_levels, milestone_bonus = Config.Curve.milestone_bonus,
  }
end

return Config
