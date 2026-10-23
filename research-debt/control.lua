local Debt = require("scripts.debt")
local Archive = require("scripts.archive")
local Values = require("scripts.values")
local Gui = require("scripts.gui")
local Trades = require("scripts.trades")
local Bonus = require("scripts.bonus")
local Tiers = require("scripts.tiers")
local Requests = require("scripts.requests")
local Config = require("scripts.config")
local Consolidation = require("scripts.consolidation")

local function fmt(x) return string.format("%.2f", x) end

-- Research events ----------------------------------------------------------

local function notify(force, key, ...)
  if settings.global["rd-chat-notifications"].value and force and force.valid then
    force.print({ key, ... })
  end
end

local function on_research_finished(event)
  local tech = event.research
  if not (tech and tech.valid) then return end
  local proto = tech.prototype
  local force = tech.force
  if Consolidation.is(proto.name) then
    local tier = Consolidation.tier_of(proto.name) or 1
    local x = math.min(storage.debt, Debt.consolidation_value(storage.debt, tier))
    storage.consolidation_removed = storage.consolidation_removed or {}
    table.insert(storage.consolidation_removed, x) -- so a reversed level gives back exactly this
    storage.stats.consolidation_levels = storage.stats.consolidation_levels + 1
    storage.stats.consolidation_debt = storage.stats.consolidation_debt - x
    local _, m = Debt.add(-x, "consolidation", proto.name .. " level " .. (tech.researched and tech.level or tech.level - 1), force)
    notify(force, "research-debt.msg-consolidation", fmt(x), fmt(m))
    local levels = Consolidation.levels_completed(force)
    local reached, total = Bonus.update_milestones(force, levels)
    if reached then
      notify(force, "research-debt.msg-milestone", levels, string.format("%d%%", math.floor(total * 100 + 0.5)))
    end
    return
  end
  -- any technology may unlock the next consolidation tier
  Consolidation.update_tiers(force)
  if not Debt.counts(proto) then return end
  local step = Debt.step_for(proto)
  storage.stats.techs_counted = storage.stats.techs_counted + 1
  storage.stats.techs_debt = storage.stats.techs_debt + step
  local _, m = Debt.add(step, "research", proto.name, force)
  notify(force, "research-debt.msg-research", proto.localised_name, fmt(step), fmt(m))
end

local function on_research_reversed(event)
  local tech = event.research
  if not (tech and tech.valid) then return end
  local proto = tech.prototype
  if Consolidation.is(proto.name) then
    local removed = storage.consolidation_removed or {}
    local x = table.remove(removed) or Config.consolidation_min()
    storage.stats.consolidation_levels = math.max(0, storage.stats.consolidation_levels - 1)
    storage.stats.consolidation_debt = storage.stats.consolidation_debt + x
    Debt.add(x, "consolidation-reversed", proto.name, tech.force)
    Bonus.update_milestones(tech.force, Consolidation.levels_completed(tech.force))
    return
  end
  Consolidation.update_tiers(tech.force)
  if not Debt.counts(proto) then return end
  local step = Debt.step_for(proto)
  storage.stats.reversed = storage.stats.reversed + 1
  storage.stats.reversed_debt = storage.stats.reversed_debt - step
  Debt.add(-step, "reversed", proto.name, tech.force)
end

script.on_event(defines.events.on_research_finished, on_research_finished)
if defines.events.on_research_reversed then
  script.on_event(defines.events.on_research_reversed, on_research_reversed)
end

Archive.register_events()
Gui.register_events()
Trades.register_events()

-- Every debt change updates the debt-free bonus and refreshes HUDs and open windows.
Debt.on_changed = function()
  Bonus.update()
  Gui.refresh_all()
end

Bonus.on_tier_changed = function(force, old_mod, new_mod)
  local pct = string.format("%+d%%", math.floor(new_mod * 100 + 0.5))
  if new_mod > old_mod then
    notify(force, "research-debt.msg-labs-faster", pct)
  else
    notify(force, "research-debt.msg-labs-slower", pct)
  end
end

-- reset_technology_effects() wipes all script modifiers: restore ours.
script.on_event(defines.events.on_technology_effects_reset, function(event)
  Trades.reapply_lab_penalty(event.force)
  Bonus.reapply(event.force)
end)

script.on_event(defines.events.on_force_created, function()
  Bonus.update()
  Consolidation.update_all_forces()
end)

Requests.on_new = function(req)
  for _, force in pairs(game.forces) do
    if force.research_enabled and force.name ~= "enemy" and force.name ~= "neutral" then
      notify(force, "research-debt.msg-request-new", req.amount, "[item=" .. req.item .. "]",
        prototypes.item[req.item].localised_name, req.bonus, Config.request_interval())
    end
  end
  Gui.refresh_all()
end

Requests.on_done = function(req)
  for _, force in pairs(game.forces) do
    if force.research_enabled and force.name ~= "enemy" and force.name ~= "neutral" then
      notify(force, "research-debt.msg-request-done", req.amount, "[item=" .. req.item .. "]", prototypes.item[req.item].localised_name)
    end
  end
end

-- One periodic handler for the whole mod.
script.on_nth_tick(Values.Balance.process_interval, function()
  Requests.tick()
  Archive.process_all()
  -- Watchdog: settings changed by script, or another mod writing the multiplier.
  local want = Debt.compute_multiplier(storage.debt)
  if math.abs(game.difficulty_settings.technology_price_multiplier - want) > 1e-9 then
    Debt.add(0, "watchdog", "multiplier drifted")
  end
  Gui.tick()
end)

-- Lifecycle ----------------------------------------------------------------

script.on_init(function()
  Debt.init_storage()
  Debt.apply_multiplier()
  Bonus.update()
  Consolidation.update_all_forces()
  log(string.format("[research-debt] init: base_multiplier=%.4f debt=%.4f", storage.base_multiplier, storage.debt))
end)

script.on_configuration_changed(function(data)
  local fresh = (storage.base_multiplier == nil)
  Debt.init_storage()
  local mod_change = data.mod_changes and data.mod_changes["research-debt"]
  if fresh or (mod_change and mod_change.old_version == nil) then
    -- Mod added to an existing save: derive debt from what has already been researched.
    local n = Debt.recalculate("recalc-added")
    log(string.format("[research-debt] added to existing save: %d counted technologies, debt=%.4f", n, storage.debt))
  else
    Debt.apply_multiplier()
  end
  Bonus.update()
  Consolidation.update_all_forces()
  -- Prototype set may have changed (archive enabled/disabled, other mods): rebuild registry.
  Archive.rescan()
  for _, player in pairs(game.players) do
    Gui.close(player)
    local rel = player.gui.relative["rd-lab-panel"]
    if rel then rel.destroy() end
    Gui.update_hud(player)
    Gui.update_lab_panel(player)
  end
end)

script.on_event(defines.events.on_runtime_mod_setting_changed, function(event)
  if not (event.setting and event.setting:sub(1, 3) == "rd-") then return end
  if event.setting_type == "runtime-global" then
    Debt.add(0, "setting", event.setting)
  elseif event.setting_type == "runtime-per-user" then
    Gui.on_setting_changed(event)
  end
end)

-- Commands -----------------------------------------------------------------

local function status_text()
  local s = Debt.status()
  return string.format("[Research Debt] debt=%.4f base=%.4f multiplier=%.4f (raw %.4f, limits %.3f..%.3f) mode=%s step=%.3f | techs=%d consolidation=%d archive_items=%d archives=%d",
    s.debt, s.base_multiplier, s.actual_multiplier, s.raw_multiplier, s.min_multiplier, s.max_multiplier,
    s.growth_mode, s.step, s.stats.techs_counted, s.stats.consolidation_levels, s.stats.archive_items, s.archives)
end

local function reply(cmd, text)
  if cmd.player_index then
    local p = game.get_player(cmd.player_index)
    if p then p.print(text) end
  else
    rcon.print(text)
  end
end

local function is_admin(cmd)
  if not cmd.player_index then return true end
  local p = game.get_player(cmd.player_index)
  return p and p.admin
end

commands.add_command("rd-status", { "research-debt.cmd-status" }, function(cmd)
  reply(cmd, status_text())
end)

commands.add_command("rd-recalc", { "research-debt.cmd-recalc" }, function(cmd)
  if not is_admin(cmd) then reply(cmd, { "research-debt.admin-only" }) return end
  local n = Debt.recalculate("recalc-command")
  local a = Archive.rescan()
  reply(cmd, string.format("[Research Debt] recalculated from %d researched technologies, %d archives found. %s", n, a, status_text()))
end)

commands.add_command("rd-reset", { "research-debt.cmd-reset" }, function(cmd)
  if not is_admin(cmd) then reply(cmd, { "research-debt.admin-only" }) return end
  Trades.reset_all()
  Requests.reset()
  Debt.reset()
  reply(cmd, "[Research Debt] reset. " .. status_text())
end)

commands.add_command("rd-gui", { "research-debt.cmd-gui" }, function(cmd)
  if not cmd.player_index then reply(cmd, "[Research Debt] /rd-gui needs a player.") return end
  Gui.toggle(game.get_player(cmd.player_index))
end)

-- Remote interface (testing + compatibility) --------------------------------

remote.add_interface("research-debt", {
  status = function() return Debt.status() end,
  add_debt = function(x, reason) return Debt.add(x, reason or "script", "remote") end,
  reset = function() Trades.reset_all() Requests.reset() Debt.reset() return Debt.status() end,
  request = function() return storage.request end,
  request_queue = function() return Requests.upcoming() end,
  request_candidates = function() return Requests.candidates() end,
  new_request = function(item, amount) return Requests.new(item, amount) end,
  expire_request = function() if storage.request then storage.request.expires_tick = game.tick end Requests.tick() return storage.request end,
  recalculate = function() local n = Debt.recalculate("recalc-remote") return n end,
  set_base = function(x)
    storage.base_multiplier = x
    Debt.add(0, "set-base", tostring(x))
    return Debt.status()
  end,
  counts = function(tech_name)
    local proto = prototypes.technology[tech_name]
    if not proto then return nil end
    return { counts = Debt.counts(proto), infinite = Debt.is_infinite(proto), max_level = proto.max_level, trigger = proto.research_trigger ~= nil }
  end,
  step_for = function(tech_name)
    local proto = prototypes.technology[tech_name]
    if not proto then return nil end
    return { step = Debt.step_for(proto), tier = Tiers.tier_of(proto), factor = Tiers.factor(proto) }
  end,
  bonus = function(force_name)
    local f = game.forces[force_name or "player"]
    return { modifier = Bonus.current_modifier(), applied = Bonus.applied(f), milestones = Bonus.milestones_applied(f),
             lab_speed = f.laboratory_speed_modifier, lab_productivity = f.laboratory_productivity_bonus }
  end,
  config = function() return Config.resolved() end,
  consolidation = function(force_name)
    local st = Consolidation.state(game.forces[force_name or "player"])
    st.tech = nil -- not JSON-serialisable
    st.value = Consolidation.value(game.forces[force_name or "player"], storage.debt)
    return st
  end,
  lab_curve = function() return Config.lab_curve() end,
  history = function() return storage.history end,
  archive_value = function(item_name, quality)
    local v = Values.value(item_name)
    if not v then return nil end
    return v * Values.quality_multiplier(quality)
  end,
  archive_preview = function(points)
    return Values.effective_points(storage.total_offered, points) * Values.Balance.debt_per_point
  end,
  archive_process_now = function() Archive.process_all() return Debt.status() end,
  balance = function()
    local b = {}
    for k, v in pairs(Values.Balance) do b[k] = v end
    b.half_life = Values.half_life()
    return b
  end,
  open_gui = function(player_index) Gui.open(game.get_player(player_index)) end,
  gui_toggle = function(player_index, what) Gui.toggle_section(game.get_player(player_index), what) end,
  -- only the owning mod may write its runtime-global settings
  set_setting = function(name, value)
    settings.global[name] = { value = value }
    Debt.add(0, "setting", name)
    return Debt.status()
  end,
  -- trades
  trade_lab = function(force_name) return Trades.lab_slow(game.forces[force_name]) end,
  trade_lab_undo = function(force_name) return Trades.lab_restore(game.forces[force_name]) end,
  trade_evolution = function(force_name, surface_index) return Trades.evolution_trade(game.forces[force_name], game.surfaces[surface_index or 1]) end,
  forgettable = function(force_name) return Trades.forgettable(game.forces[force_name]) end,
  forget = function(force_name, tech_name) return Trades.forget(game.forces[force_name], tech_name) end,
  trades_state = function(force_name) return Trades.state(game.forces[force_name]) end,
})
