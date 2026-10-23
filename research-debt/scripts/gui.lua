-- In-game GUI: explains what the multiplier is, why it is what it is, and what the
-- player can do about it. One window per player (player.gui.screen) plus a small HUD
-- button in player.gui.top. Everything is rebuilt from storage on every change, so the
-- GUI never holds state of its own except "which sections are expanded".
local Debt = require("scripts.debt")
local Values = require("scripts.values")
local Archive = require("scripts.archive")
local Trades = require("scripts.trades")
local Tiers = require("scripts.tiers")
local Bonus = require("scripts.bonus")
local Requests = require("scripts.requests")
local Config = require("scripts.config")

local Gui = {}

Gui.WINDOW = "rd-main"
Gui.HUD = "rd-hud"
Gui.SHORTCUT = "rd-toggle-gui"
Gui.HISTORY_SHOWN = 8
Gui.VALUE_ROWS = 12

local GREEN = { r = 0.55, g = 0.95, b = 0.55 }
local ORANGE = { r = 1, g = 0.75, b = 0.35 }
local RED = { r = 1, g = 0.45, b = 0.45 }
local GREY = { r = 0.7, g = 0.7, b = 0.7 }

local function fmt2(x) return string.format("%.2f", x) end
local function fmt3(x) return string.format("%.3f", x) end
local function fmtx(x) return string.format("×%.2f", x) end
local function fmt_pct(x) return string.format("%d%%", math.floor(x * 100 + 0.5)) end
local function fmt_signed(x, digits)
  return string.format("%+." .. (digits or 2) .. "f", x)
end
local function fmt_signed_pct(x)
  return string.format("%+d%%", math.floor(x * 100 + 0.5))
end
local function fmt_int(n)
  local s = tostring(math.floor(n + 0.5))
  -- gsub returns (string, count); keep only the string so callers never get a stray number
  local grouped = s:reverse():gsub("(%d%d%d)", "%1 "):reverse()
  return (grouped:gsub("^ ", ""))
end
local function fmt_time(tick)
  local s = math.floor(tick / 60)
  return string.format("%d:%02d:%02d", math.floor(s / 3600), math.floor(s / 60) % 60, s % 60)
end

local function pstate(player_index)
  storage.gui = storage.gui or {}
  local st = storage.gui[player_index]
  if not st then
    st = { log_open = false, values_open = false }
    storage.gui[player_index] = st
  end
  return st
end

-- Helpers ------------------------------------------------------------------

local function add_label(parent, caption, style, color, tooltip)
  local l = parent.add({ type = "label", caption = caption, style = style or "label", tooltip = tooltip })
  if color then l.style.font_color = color end
  return l
end

local function add_para(parent, caption, width, color)
  local l = parent.add({ type = "label", caption = caption })
  l.style.single_line = false
  l.style.maximal_width = width or 520
  if color then l.style.font_color = color end
  return l
end

local function signed_color(v)
  if v > 0.0005 then return ORANGE elseif v < -0.0005 then return GREEN else return GREY end
end

local function add_row(tbl, left, right, right_color, tooltip, bold)
  add_label(tbl, left, nil, nil, tooltip)
  local r = add_label(tbl, right, bold and "bold_label" or "label", right_color, tooltip)
  r.style.horizontal_align = "right"
  r.style.horizontally_stretchable = true
  return r
end

local function card(parent, title, tooltip)
  local f = parent.add({ type = "frame", style = "bordered_frame", direction = "vertical" })
  f.style.horizontally_stretchable = true
  add_label(f, title, "caption_label", nil, tooltip)
  return f
end

-- Consolidation status for a force -----------------------------------------

local function consolidation_state(force)
  local tech = force.technologies[Debt.CONSOLIDATION_TECH]
  if not tech then return nil end
  local prereqs_ok = true
  local missing = nil
  for name, pre in pairs(tech.prerequisites) do
    if not pre.researched then
      prereqs_ok = false
      missing = missing or pre.localised_name
    end
  end
  local queued, researching, progress = false, false, 0
  if force.current_research and force.current_research.name == tech.name then
    researching = true
    progress = force.research_progress
  end
  for _, q in pairs(force.research_queue) do
    if q.name == tech.name then queued = true end
  end
  return {
    tech = tech,
    available = tech.enabled and prereqs_ok,
    missing = missing,
    queued = queued,
    researching = researching,
    progress = progress,
    units = tech.research_unit_count,
    ingredients = tech.research_unit_ingredients,
    level = tech.level,
  }
end

local function ingredients_rich(ingredients)
  local parts = {}
  for _, ing in pairs(ingredients) do
    parts[#parts + 1] = string.format("[%s=%s]", ing.type or "item", ing.name)
  end
  return table.concat(parts, " ")
end

-- Sections -----------------------------------------------------------------

local function build_summary(parent, s, player)
  local flow = parent.add({ type = "flow", direction = "horizontal" })
  flow.style.vertical_align = "center"
  flow.style.horizontal_spacing = 16
  local big = add_label(flow, fmtx(s.actual_multiplier), "heading_2_label",
    s.debt > 0 and ORANGE or GREEN, { "research-debt.gui-multiplier-tooltip" })
  big.style.font = "default-large-bold"
  local right = flow.add({ type = "flow", direction = "vertical" })
  add_label(right, { "research-debt.gui-current-cost" }, "caption_label")
  local formula
  if s.growth_mode == "exponential" then
    formula = { "research-debt.gui-formula-exponential", fmt2(s.base_multiplier), fmt2(1 + s.step), fmt2(s.debt / math.max(s.step, 1e-9)), fmtx(s.raw_multiplier) }
  else
    formula = { "research-debt.gui-formula-linear", fmt2(s.base_multiplier), fmt2(s.debt), fmtx(s.raw_multiplier) }
  end
  add_label(right, formula, "label", GREY)
  if math.abs(s.raw_multiplier - s.actual_multiplier) > 1e-9 then
    add_label(right, { "research-debt.gui-clamped", fmtx(s.min_multiplier), fmtx(s.max_multiplier) }, "label", RED)
  end
  -- what the next technology will do
  local cur = player.force.current_research
  if cur and Debt.counts(cur.prototype) then
    local st = Debt.step_for(cur.prototype)
    add_label(right, { "research-debt.gui-next-tech-current", cur.localised_name, fmt2(st), fmtx(Debt.compute_multiplier(s.debt + st)) },
      "label", GREY, { "research-debt.gui-next-tech-tooltip" })
  elseif Tiers.enabled() then
    local lo = s.step * Tiers.factor_for_tier(1)
    local hi = s.step * Tiers.factor_for_tier(Tiers.max_tier())
    add_label(right, { "research-debt.gui-next-tech-range", fmt2(lo), fmt2(hi), fmtx(Debt.compute_multiplier(s.debt + lo)), fmtx(Debt.compute_multiplier(s.debt + hi)) },
      "label", GREY, { "research-debt.gui-next-tech-tooltip" })
  else
    local next_m = Debt.compute_multiplier(s.debt + s.step)
    add_label(right, { "research-debt.gui-next-tech", fmt2(s.step), fmtx(next_m) }, "label", GREY,
      { "research-debt.gui-next-tech-tooltip" })
  end
  -- lab speed curve
  local cur, better, worse = Bonus.describe(s.debt)
  if cur then
    local color = cur.modifier > 0 and GREEN or (cur.modifier < 0 and RED or GREY)
    local line
    if better and better.to ~= nil then
      line = { "research-debt.gui-curve-line", fmt_signed_pct(cur.modifier), fmt_signed_pct(better.modifier), fmt3(math.max(0, s.debt - better.to)) }
    else
      line = { "research-debt.gui-curve-line-top", fmt_signed_pct(cur.modifier) }
    end
    add_label(right, line, cur.modifier ~= 0 and "bold_label" or "label", color, { "research-debt.gui-curve-tooltip" })
  end
end

-- One line per science tier: which packs, how much debt per technology.
local function build_tier_legend(parent, s)
  if not Tiers.enabled() then return end
  local tbl = parent.add({ type = "table", column_count = 2 })
  tbl.style.column_alignments[2] = "right"
  tbl.style.horizontal_spacing = 12
  for _, row in ipairs(Tiers.table()) do
    local icons = {}
    for _, name in ipairs(row.packs) do icons[#icons + 1] = string.format("[item=%s]", name) end
    add_label(tbl, { "research-debt.gui-tier-row", row.tier, table.concat(icons, "") }, "label", GREY,
      { "research-debt.gui-tier-tooltip" })
    add_label(tbl, fmt_signed(s.step * row.factor), "label", ORANGE)
  end
end

local function build_breakdown(parent, s)
  local st = s.stats
  add_label(parent, { "research-debt.gui-why-title" }, "caption_label")
  if Tiers.enabled() then
    add_para(parent, { "research-debt.gui-why-text-tiered" }, 560, GREY)
  else
    add_para(parent, { "research-debt.gui-why-text", fmt2(s.step) }, 560, GREY)
  end
  local tbl = parent.add({ type = "table", column_count = 2 })
  tbl.style.horizontally_stretchable = true
  tbl.style.column_alignments[2] = "right"
  if Tiers.enabled() then
    add_row(tbl, { "research-debt.gui-row-techs-tiered", fmt_int(st.techs_counted) }, fmt_signed(st.techs_debt), signed_color(st.techs_debt),
      { "research-debt.gui-row-techs-tooltip" })
  else
    add_row(tbl, { "research-debt.gui-row-techs", fmt_int(st.techs_counted), fmt2(s.step) }, fmt_signed(st.techs_debt), signed_color(st.techs_debt),
      { "research-debt.gui-row-techs-tooltip" })
  end
  if st.reversed > 0 then
    add_row(tbl, { "research-debt.gui-row-reversed", fmt_int(st.reversed) }, fmt_signed(st.reversed_debt), signed_color(st.reversed_debt))
  end
  add_row(tbl, { "research-debt.gui-row-consolidation", fmt_int(st.consolidation_levels) }, fmt_signed(st.consolidation_debt), signed_color(st.consolidation_debt))
  if Archive.enabled() then
    add_row(tbl, { "research-debt.gui-row-archive", fmt_int(st.archive_items) }, fmt_signed(st.archive_debt, 3), signed_color(st.archive_debt))
  end
  if Trades.enabled() and st.trades_debt ~= 0 then
    add_row(tbl, { "research-debt.gui-row-trades" }, fmt_signed(st.trades_debt), signed_color(st.trades_debt))
  end
  local accounted = st.techs_debt + st.reversed_debt + st.consolidation_debt + st.archive_debt + st.trades_debt
  local other = s.debt - accounted
  if math.abs(other) > 0.0005 then
    add_row(tbl, { "research-debt.gui-row-other" }, fmt_signed(other), GREY, { "research-debt.gui-row-other-tooltip" })
  end
  add_row(tbl, { "research-debt.gui-row-total" }, fmt3(s.debt), nil, nil, true)
end

local function build_consolidation_card(parent, player, s)
  local force = player.force
  local c = card(parent, { "research-debt.gui-cons-title" })
  local cs = consolidation_state(force)
  if not cs then
    add_para(c, { "research-debt.gui-cons-missing" }, 560, RED)
    return
  end
  local after = Debt.compute_multiplier(math.max(0, s.debt - s.consolidation_value))
  add_para(c, { "research-debt.gui-cons-text-percent", fmt_pct(s.consolidation_percent), fmt2(s.consolidation_min),
    fmt2(s.consolidation_value), fmtx(after) }, 560)
  local C = Config.Curve
  local done = cs.level - 1
  local next_ms = (math.floor(done / C.milestone_levels) + 1) * C.milestone_levels
  add_label(c, { "research-debt.gui-cons-milestone", fmt_pct(C.milestone_bonus), C.milestone_levels, next_ms,
    fmt_signed_pct(Bonus.milestones_applied(force)) }, "label", Bonus.milestones_applied(force) > 0 and GREEN or GREY,
    { "research-debt.gui-cons-milestone-tooltip" })
  add_label(c, { "research-debt.gui-cons-cost", cs.level, fmt_int(cs.units), ingredients_rich(cs.ingredients) }, "label", GREY)
  local row = c.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  local status = add_label(row, "", "label")
  status.name = "rd-cons-status"
  local spacer = row.add({ type = "empty-widget" })
  spacer.style.horizontally_stretchable = true
  local btn = row.add({
    type = "button", name = "rd-cons-queue", caption = { "research-debt.gui-cons-queue" },
    tooltip = { "research-debt.gui-cons-queue-tooltip" },
    tags = { rd_action = "queue_consolidation" },
  })
  Gui.update_consolidation_status(status, btn, cs, s)
end

-- Updates the live part of the consolidation card without rebuilding (keeps scroll position).
function Gui.update_consolidation_status(status, btn, cs, s)
  local caption, color
  if cs.researching then
    caption, color = { "research-debt.gui-cons-researching", fmt_pct(cs.progress) }, GREEN
  elseif cs.queued then
    caption, color = { "research-debt.gui-cons-queued" }, GREEN
  elseif not cs.available then
    caption, color = { "research-debt.gui-cons-locked", cs.missing or "?" }, RED
  elseif s.debt <= 0 then
    caption, color = { "research-debt.gui-cons-nodebt" }, GREY
  else
    caption, color = { "research-debt.gui-cons-available" }, GREEN
  end
  status.caption = caption
  status.style.font_color = color
  btn.enabled = cs.available and not cs.queued and not cs.researching
end

local function find_element(el, name)
  if not (el and el.valid) then return nil end
  if el.name == name then return el end
  for _, c in pairs(el.children) do
    local f = find_element(c, name)
    if f then return f end
  end
  return nil
end

local function build_archive_card(parent, player, s, st)
  if not Archive.enabled() then return end
  local force = player.force
  local c = card(parent, { "research-debt.gui-arch-title" })
  local eff = Values.efficiency(s.total_offered)
  add_para(c, { "research-debt.gui-arch-text" }, 560)
  local tech = force.technologies["rd-archive"]
  local status_color, status
  if tech and not tech.researched then
    status, status_color = { "research-debt.gui-arch-locked" }, RED
  elseif s.archives == 0 then
    status, status_color = { "research-debt.gui-arch-none" }, ORANGE
  else
    status, status_color = { "research-debt.gui-arch-count", s.archives }, GREEN
  end
  add_label(c, status, "label", status_color)
  add_label(c, { "research-debt.gui-arch-efficiency", fmt_pct(eff), fmt_int(Values.half_life()) }, "label",
    eff > 0.5 and GREEN or (eff > 0.2 and ORANGE or RED), { "research-debt.gui-arch-efficiency-tooltip" })
  -- a concrete example: how many processing units (or best available item) for one tech step
  local example = prototypes.item["processing-unit"] and "processing-unit" or nil
  if not example then
    local list = Values.available_items()
    if list[1] then example = list[1].name end
  end
  if example then
    local per_item = Values.value(example) * eff * Values.Balance.debt_per_point
    if per_item > 0 then
      add_label(c, { "research-debt.gui-arch-example", example, fmt_int(math.ceil(s.step / per_item)), fmt2(s.step) }, "label", GREY)
    end
  end
  -- current request
  if Requests.enabled() then
    local req = Requests.current()
    if req then
      local minutes = math.max(0, math.floor((req.expires_tick - game.tick) / 3600))
      local per_item = Values.value(req.item) * req.bonus * eff * Values.Balance.debt_per_point
      local l = add_para(c, { "research-debt.gui-arch-request", req.amount, req.item, prototypes.item[req.item].localised_name,
        req.bonus, req.delivered, minutes, fmt3(per_item * (req.amount - req.delivered)) }, 560, ORANGE)
      l.name = "rd-request"
      l.tooltip = { "research-debt.gui-arch-request-tooltip" }
    else
      local wait = storage.next_request_tick and math.max(0, math.ceil((storage.next_request_tick - game.tick) / 3600)) or 0
      add_label(c, { "research-debt.gui-arch-request-none", wait }, "label", GREY, { "research-debt.gui-arch-request-tooltip" })
    end
    local queue = Requests.upcoming()
    if #queue > 0 then
      local parts = {}
      for _, q in ipairs(queue) do parts[#parts + 1] = string.format("%d × [item=%s]", q.amount, q.item) end
      add_label(c, { "research-debt.gui-arch-upcoming", table.concat(parts, "   ") }, "label", GREY,
        { "research-debt.gui-arch-upcoming-tooltip" })
    end
  end
  local row = c.add({ type = "flow", direction = "horizontal" })
  local spacer = row.add({ type = "empty-widget" })
  spacer.style.horizontally_stretchable = true
  row.add({
    type = "button", caption = { st.values_open and "research-debt.gui-arch-hide-values" or "research-debt.gui-arch-show-values" },
    tags = { rd_action = "toggle_values" },
  })
  if st.values_open then
    local scroll = c.add({ type = "scroll-pane", vertical_scroll_policy = "auto" })
    scroll.style.maximal_height = 220
    local tbl = scroll.add({ type = "table", column_count = 3, draw_horizontal_lines = true })
    tbl.style.column_alignments[2] = "right"
    tbl.style.column_alignments[3] = "right"
    add_label(tbl, { "research-debt.gui-arch-col-item" }, "bold_label")
    add_label(tbl, { "research-debt.gui-arch-col-value" }, "bold_label")
    add_label(tbl, { "research-debt.gui-arch-col-per-step" }, "bold_label")
    for i, it in ipairs(Values.available_items()) do
      if i > Gui.VALUE_ROWS then break end
      local per_item = it.points * eff * Values.Balance.debt_per_point
      add_label(tbl, string.format("[item=%s] ", it.name) .. "[font=default-semibold]" .. "[/font]", nil, nil, prototypes.item[it.name].localised_name)
      tbl.children[#tbl.children].caption = { "", string.format("[item=%s] ", it.name), prototypes.item[it.name].localised_name }
      add_label(tbl, string.format("%.4f", per_item))
      add_label(tbl, fmt_int(math.ceil(s.step / per_item)))
    end
    add_label(c, { "research-debt.gui-arch-quality", fmt2(1 + Values.Balance.quality_bonus), fmt2(1 + 5 * Values.Balance.quality_bonus) }, "label", GREY)
  end
end

local function build_trades_cards(parent, player, s)
  if not Trades.enabled() then return end
  local force = player.force
  local B = Trades.Balance
  local ts = Trades.state(force)
  local nodebt = s.debt <= 0

  -- labs
  local c = card(parent, { "research-debt.gui-trade-lab-title" })
  add_para(c, { "research-debt.gui-trade-lab-text", fmt_pct(B.lab_step), fmt2(B.lab_debt) }, 560)
  add_label(c, { "research-debt.gui-trade-lab-status", fmt_pct(ts.lab_penalty), ts.lab_steps, ts.lab_max_steps, fmt_signed(ts.lab_modifier) },
    "label", ts.lab_steps > 0 and ORANGE or GREY)
  local row = c.add({ type = "flow", direction = "horizontal" })
  local spacer = row.add({ type = "empty-widget" })
  spacer.style.horizontally_stretchable = true
  local undo = row.add({ type = "button", caption = { "research-debt.gui-trade-lab-restore", fmt_pct(B.lab_step), fmt2(B.lab_debt) }, tags = { rd_action = "trade_lab_undo" } })
  undo.enabled = ts.lab_steps > 0
  local slow = row.add({ type = "button", caption = { "research-debt.gui-trade-lab-slow", fmt_pct(B.lab_step), fmt2(B.lab_debt) }, tags = { rd_action = "trade_lab" } })
  slow.enabled = ts.lab_steps < ts.lab_max_steps and not nodebt
  if nodebt then slow.tooltip = { "research-debt.gui-trade-nodebt" } end

  -- evolution
  c = card(parent, { "research-debt.gui-trade-evo-title" })
  add_para(c, { "research-debt.gui-trade-evo-text", fmt_pct(B.evo_step), fmt2(B.evo_debt) }, 560)
  local surface = player.surface
  local evo = Trades.evolution_info(surface)
  row = c.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  if evo == nil then
    add_label(row, { "research-debt.gui-trade-evo-none" }, "label", GREY)
  elseif evo >= B.evo_max then
    add_label(row, { "research-debt.gui-trade-evo-max", fmt_pct(B.evo_max) }, "label", RED)
  else
    add_label(row, { "research-debt.gui-trade-evo-status", surface.name, fmt_pct(evo) }, "label", evo > 0.7 and ORANGE or GREY)
  end
  spacer = row.add({ type = "empty-widget" })
  spacer.style.horizontally_stretchable = true
  local evo_btn = row.add({ type = "button", caption = { "research-debt.gui-trade-evo-button", fmt_pct(B.evo_step), fmt2(B.evo_debt) }, tags = { rd_action = "trade_evo" } })
  evo_btn.enabled = evo ~= nil and evo < B.evo_max and not nodebt
  if nodebt then evo_btn.tooltip = { "research-debt.gui-trade-nodebt" } end

  -- forget
  c = card(parent, { "research-debt.gui-trade-forget-title" })
  add_para(c, { "research-debt.gui-trade-forget-text", fmt2(s.step) }, 560)
  local names = Trades.forgettable(force)
  row = c.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  if #names == 0 then
    add_label(row, { "research-debt.gui-trade-forget-none" }, "label", GREY)
  else
    local items = {}
    for i, name in ipairs(names) do
      local proto = prototypes.technology[name]
      items[i] = { "", string.format("[img=technology/%s] ", name), proto and proto.localised_name or name }
    end
    local dd = row.add({ type = "drop-down", name = "rd-forget-dropdown", items = items, selected_index = 1, tags = { names = names } })
    dd.style.minimal_width = 320
    spacer = row.add({ type = "empty-widget" })
    spacer.style.horizontally_stretchable = true
    row.add({ type = "button", caption = { "research-debt.gui-trade-forget-button" }, tags = { rd_action = "forget_tech" }, style = "red_button" })
  end
end

local function build_bonus_card(parent, s)
  local c = card(parent, { "research-debt.gui-curve-title" })
  add_para(c, { "research-debt.gui-curve-text" }, 560)
  local cur = Bonus.describe(s.debt)
  local tbl = c.add({ type = "table", column_count = 2 })
  tbl.style.column_alignments[2] = "right"
  tbl.style.horizontal_spacing = 16
  for _, r in ipairs(Config.lab_curve()) do
    local range
    if r.from == nil then range = { "research-debt.gui-curve-row-zero" }
    elseif r.to == nil then range = { "research-debt.gui-curve-row-above", fmt2(r.from) }
    else range = { "research-debt.gui-curve-row-between", fmt2(r.from), fmt2(r.to) } end
    local is_cur = cur and r.from == cur.from and r.to == cur.to
    add_label(tbl, range, is_cur and "bold_label" or "label", is_cur and nil or GREY)
    add_label(tbl, fmt_signed_pct(r.modifier), is_cur and "bold_label" or "label",
      r.modifier > 0 and GREEN or (r.modifier < 0 and RED or GREY))
  end
end

local function build_info_card(parent)
  local c = card(parent, { "research-debt.gui-free-title" })
  add_para(c, { "research-debt.gui-free-text" }, 560, GREY)
end

local function build_history(parent, st)
  local row = parent.add({ type = "flow", direction = "horizontal" })
  row.style.vertical_align = "center"
  add_label(row, { "research-debt.gui-log-title" }, "caption_label")
  local spacer = row.add({ type = "empty-widget" })
  spacer.style.horizontally_stretchable = true
  row.add({ type = "button", caption = { st.log_open and "research-debt.gui-hide" or "research-debt.gui-show" }, tags = { rd_action = "toggle_log" } })
  if not st.log_open then return end
  local h = storage.history
  if #h == 0 then
    add_label(parent, { "research-debt.gui-log-empty" }, "label", GREY)
    return
  end
  local tbl = parent.add({ type = "table", column_count = 3 })
  tbl.style.column_alignments[2] = "right"
  for i = #h, math.max(1, #h - Gui.HISTORY_SHOWN + 1), -1 do
    local e = h[i]
    add_label(tbl, fmt_time(e.tick), "label", GREY)
    add_label(tbl, fmt_signed(e.delta, 3), "bold_label", e.delta > 0 and ORANGE or (e.delta < 0 and GREEN or GREY))
    local what
    if e.reason == "research" then
      local proto = prototypes.technology[e.detail]
      what = { "research-debt.gui-log-research", proto and proto.localised_name or tostring(e.detail), fmtx(e.multiplier) }
    elseif e.reason == "reversed" then
      local proto = prototypes.technology[e.detail]
      what = { "research-debt.gui-log-reversed", proto and proto.localised_name or tostring(e.detail), fmtx(e.multiplier) }
    elseif e.reason == "consolidation" then
      what = { "research-debt.gui-log-consolidation", fmtx(e.multiplier) }
    elseif e.reason == "archive" then
      what = { "research-debt.gui-log-archive", tostring(e.detail), fmtx(e.multiplier) }
    elseif e.reason:sub(1, 6) == "trade-" then
      what = { "research-debt.gui-log-trade", tostring(e.detail), fmtx(e.multiplier) }
    else
      what = { "research-debt.gui-log-other", tostring(e.reason), fmtx(e.multiplier) }
    end
    add_label(tbl, what)
  end
end

-- Window -------------------------------------------------------------------

function Gui.is_open(player)
  return player.gui.screen[Gui.WINDOW] ~= nil
end

function Gui.close(player)
  local w = player.gui.screen[Gui.WINDOW]
  if w then w.destroy() end
  if player.opened_gui_type == defines.gui_type.custom and player.opened == nil then
    -- nothing
  end
  player.set_shortcut_toggled(Gui.SHORTCUT, false)
end

function Gui.open(player)
  Gui.close(player)
  local frame = player.gui.screen.add({ type = "frame", name = Gui.WINDOW, direction = "vertical" })
  frame.auto_center = true
  -- title bar
  local bar = frame.add({ type = "flow", direction = "horizontal" })
  bar.drag_target = frame
  add_label(bar, { "research-debt.gui-title" }, "frame_title").drag_target = frame
  local handle = bar.add({ type = "empty-widget", style = "draggable_space_header" })
  handle.style.horizontally_stretchable = true
  handle.style.height = 24
  handle.style.right_margin = 4
  handle.drag_target = frame
  bar.add({
    type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip = { "gui.close-instruction" }, tags = { rd_action = "close" },
  })
  local content = frame.add({ type = "frame", name = "content", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  content.style.minimal_width = 580
  Gui.fill(player, content)
  player.opened = frame
  player.set_shortcut_toggled(Gui.SHORTCUT, true)
end

-- Build the window content. Any error is caught: the window closes and the error is logged
-- instead of crashing the game from a tick handler.
function Gui.fill(player, content)
  local ok, err = xpcall(Gui.fill_unsafe, debug.traceback, player, content)
  if not ok then
    log("[research-debt] GUI error: " .. tostring(err))
    local w = player.gui.screen[Gui.WINDOW]
    if w then w.destroy() end
    player.set_shortcut_toggled(Gui.SHORTCUT, false)
    player.print("[Research Debt] GUI error, see factorio-current.log: " .. tostring(err))
  end
end

function Gui.fill_unsafe(player, frame_content)
  -- The scroll pane survives refreshes so the scroll position is kept; only its content is rebuilt.
  local scroll = frame_content.scroll
  if not scroll then
    scroll = frame_content.add({ type = "scroll-pane", name = "scroll", style = "naked_scroll_pane", horizontal_scroll_policy = "never", vertical_scroll_policy = "auto" })
    local res, scale = player.display_resolution, player.display_scale
    scroll.style.maximal_height = math.max(400, math.floor(res.height / scale * 0.82))
  end
  scroll.clear()
  local content = scroll.add({ type = "flow", name = "body", direction = "vertical" })
  content.style.vertical_spacing = 10
  content.style.right_padding = 8
  local s = Debt.status()
  local st = pstate(player.index)
  build_summary(content, s, player)
  content.add({ type = "line" })
  build_breakdown(content, s)
  build_tier_legend(content, s)
  content.add({ type = "line" })
  add_label(content, { "research-debt.gui-how-title" }, "caption_label")
  build_bonus_card(content, s)
  build_consolidation_card(content, player, s)
  build_archive_card(content, player, s, st)
  build_trades_cards(content, player, s)
  build_info_card(content)
  content.add({ type = "line" })
  build_history(content, st)
  add_label(content, { "research-debt.gui-settings-hint-preset", { "research-debt.preset-" .. Config.preset_name() }, s.growth_mode, fmt2(s.step), fmtx(s.max_multiplier) }, "label", GREY,
    { "research-debt.gui-settings-hint-tooltip" })
  content.add({
    type = "checkbox", name = "rd-hud-checkbox", caption = { "research-debt.gui-hud-toggle" },
    tooltip = { "research-debt.gui-hud-toggle-tooltip" },
    state = settings.get_player_settings(player)["rd-show-hud"].value,
  })
end

function Gui.on_checked(event)
  local el = event.element
  if not (el and el.valid and el.name == "rd-hud-checkbox") then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  settings.get_player_settings(player)["rd-show-hud"] = { value = el.state }
  Gui.update_hud(player)
end

function Gui.refresh(player)
  local w = player.gui.screen[Gui.WINDOW]
  if w and w.content then Gui.fill(player, w.content) end
end

function Gui.toggle(player)
  if Gui.is_open(player) then Gui.close(player) else Gui.open(player) end
end

-- "values" or "log": expand/collapse a section (used by tests and the click handler)
function Gui.toggle_section(player, what)
  local st = pstate(player.index)
  if what == "values" then st.values_open = not st.values_open end
  if what == "log" then st.log_open = not st.log_open end
  Gui.refresh(player)
end

-- HUD ----------------------------------------------------------------------

function Gui.update_hud(player)
  local top = player.gui.top
  local show = settings.get_player_settings(player)["rd-show-hud"].value
  local hud = top[Gui.HUD]
  if not show then
    if hud then hud.destroy() end
    return
  end
  if not hud then
    hud = top.add({ type = "button", name = Gui.HUD, tags = { rd_action = "open" } })
    hud.style.minimal_width = 0
    hud.style.padding = { 0, 8 }
    hud.style.height = 36
  end
  local s = Debt.status()
  hud.caption = { "research-debt.hud-caption", fmtx(s.actual_multiplier) }
  local next_m = Debt.compute_multiplier(s.debt + s.step)
  local mod = Bonus.current_modifier()
  if mod ~= 0 then
    hud.tooltip = { "research-debt.hud-tooltip-curve", fmt3(s.debt), fmt_int(s.stats.techs_counted), fmt_signed_pct(mod) }
  else
    hud.tooltip = { "research-debt.hud-tooltip", fmt3(s.debt), fmt_int(s.stats.techs_counted), fmtx(next_m) }
  end
  if s.debt > 0 then hud.style.font_color = ORANGE else hud.style.font_color = GREEN end
end

-- Small panel attached to the lab GUI: the only research-related vanilla screen mods can anchor to.
function Gui.update_lab_panel(player)
  local rel = player.gui.relative
  local f = rel["rd-lab-panel"]
  if not f then
    f = rel.add({
      type = "frame", name = "rd-lab-panel", direction = "vertical",
      anchor = { gui = defines.relative_gui_type.lab_gui, position = defines.relative_gui_position.right },
    })
    add_label(f, { "research-debt.gui-title" }, "frame_title")
    local inner = f.add({ type = "frame", name = "inner", style = "inside_shallow_frame_with_padding", direction = "vertical" })
    inner.style.minimal_width = 220
    local m = add_label(inner, "", "heading_2_label")
    m.name = "mult"
    m.style.font = "default-large-bold"
    local l1 = add_label(inner, "", "label", GREY)
    l1.name = "line1"
    l1.style.single_line = false
    l1.style.maximal_width = 220
    local l2 = add_label(inner, "", "label", GREY)
    l2.name = "line2"
    l2.style.single_line = false
    l2.style.maximal_width = 220
    inner.add({ type = "button", name = "open", caption = { "research-debt.gui-lab-open" }, tags = { rd_action = "open" } })
  end
  local s = Debt.status()
  local inner = f.inner
  inner.mult.caption = { "research-debt.gui-lab-mult", fmtx(s.actual_multiplier) }
  inner.mult.style.font_color = s.debt > 0 and ORANGE or GREEN
  inner.line1.caption = { "research-debt.gui-lab-line1", fmt3(s.debt), fmt_int(s.stats.techs_counted) }
  local mod = Bonus.current_modifier()
  if mod ~= 0 then
    inner.line2.caption = { "research-debt.gui-lab-curve", fmt_signed_pct(mod) }
    inner.line2.style.font_color = mod > 0 and GREEN or RED
  else
    inner.line2.caption = { "research-debt.gui-lab-line2", fmtx(Debt.compute_multiplier(s.debt + s.step)) }
    inner.line2.style.font_color = GREY
  end
end

function Gui.refresh_all()
  for _, player in pairs(game.connected_players) do
    Gui.update_hud(player)
    Gui.update_lab_panel(player)
    Gui.refresh(player)
  end
end

-- Events -------------------------------------------------------------------

function Gui.on_click(event)
  local el = event.element
  if not (el and el.valid) then return end
  local action = el.tags and el.tags.rd_action
  if not action then return end
  local player = game.get_player(event.player_index)
  if not player then return end
  if action == "close" then
    Gui.close(player)
  elseif action == "open" then
    Gui.toggle(player)
  elseif action == "toggle_log" then
    local st = pstate(player.index)
    st.log_open = not st.log_open
    Gui.refresh(player)
  elseif action == "toggle_values" then
    local st = pstate(player.index)
    st.values_open = not st.values_open
    Gui.refresh(player)
  elseif action == "trade_lab" then
    local ok, why = Trades.lab_slow(player.force)
    if ok then
      local ts, s = Trades.state(player.force), Debt.status()
      player.force.print({ "research-debt.msg-trade-lab", fmt_pct(ts.lab_penalty), fmt2(Trades.Balance.lab_debt), fmt2(s.actual_multiplier) })
    else
      player.print({ "research-debt.msg-trade-failed", tostring(why) })
    end
    Gui.refresh_all()
  elseif action == "trade_lab_undo" then
    local ok, why = Trades.lab_restore(player.force)
    if ok then
      local s = Debt.status()
      player.force.print({ "research-debt.msg-trade-lab-undo", fmt_pct(Trades.Balance.lab_step), fmt2(Trades.Balance.lab_debt), fmt2(s.actual_multiplier) })
    else
      player.print({ "research-debt.msg-trade-failed", tostring(why) })
    end
    Gui.refresh_all()
  elseif action == "trade_evo" then
    local ok, result = Trades.evolution_trade(player.force, player.surface)
    if ok then
      local s = Debt.status()
      player.force.print({ "research-debt.msg-trade-evo", player.surface.name, fmt_pct(result), fmt2(Trades.Balance.evo_debt), fmt2(s.actual_multiplier) })
    else
      player.print({ "research-debt.msg-trade-failed", tostring(result) })
    end
    Gui.refresh_all()
  elseif action == "forget_tech" then
    local dd = el.parent and el.parent["rd-forget-dropdown"]
    if dd and dd.valid and dd.selected_index > 0 then
      local names = dd.tags.names
      local name = names and names[dd.selected_index]
      local tech = name and player.force.technologies[name]
      if tech then
        local ok, why = Trades.forget(player.force, name)
        if ok then
          local s = Debt.status()
          player.force.print({ "research-debt.msg-forget", tech.localised_name, fmt2(s.step), fmt2(s.actual_multiplier) })
        else
          player.print({ "research-debt.msg-trade-failed", tostring(why) })
        end
      end
    end
    Gui.refresh_all()
  elseif action == "queue_consolidation" then
    local tech = player.force.technologies[Debt.CONSOLIDATION_TECH]
    if tech then
      local ok = player.force.add_research(tech)
      if ok then
        player.print({ "research-debt.msg-queued" })
      else
        player.print({ "research-debt.msg-queue-failed" })
      end
    end
    Gui.refresh(player)
  end
end

function Gui.on_closed(event)
  if event.element and event.element.valid and event.element.name == Gui.WINDOW then
    local player = game.get_player(event.player_index)
    if player then Gui.close(player) end
  end
end

function Gui.on_shortcut(event)
  if event.prototype_name ~= Gui.SHORTCUT then return end
  local player = game.get_player(event.player_index)
  if player then Gui.toggle(player) end
end

function Gui.on_hotkey(event)
  local player = game.get_player(event.player_index)
  if player then Gui.toggle(player) end
end

function Gui.on_player(event)
  local player = game.get_player(event.player_index)
  if player then
    Gui.update_hud(player)
    Gui.update_lab_panel(player)
  end
end

function Gui.on_setting_changed(event)
  if event.setting == "rd-show-hud" and event.player_index then
    local player = game.get_player(event.player_index)
    if player then Gui.update_hud(player) end
  end
end

-- periodic refresh of open windows (research progress, queue state)
function Gui.tick()
  for _, player in pairs(game.connected_players) do
    local w = player.gui.screen[Gui.WINDOW]
    if w then
      local status = find_element(w, "rd-cons-status")
      local btn = find_element(w, "rd-cons-queue")
      local cs = consolidation_state(player.force)
      if status and btn and cs then
        Gui.update_consolidation_status(status, btn, cs, Debt.status())
      end
    end
  end
end

function Gui.register_events()
  script.on_event(defines.events.on_gui_click, Gui.on_click)
  script.on_event(defines.events.on_gui_closed, Gui.on_closed)
  script.on_event(defines.events.on_gui_checked_state_changed, Gui.on_checked)
  script.on_event(defines.events.on_lua_shortcut, Gui.on_shortcut)
  script.on_event(Gui.SHORTCUT, Gui.on_hotkey)
  script.on_event(defines.events.on_player_created, Gui.on_player)
  script.on_event(defines.events.on_player_joined_game, Gui.on_player)
  script.on_event(defines.events.on_player_changed_force, Gui.on_player)
  script.on_event(defines.events.on_research_started, function() Gui.tick() end)
end

return Gui
