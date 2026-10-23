-- Drives the Research Debt GUI in a real client and writes screenshots to script-output.
-- Only used by tests/gui_check.py.
local steps = {}
local started = nil

-- progress goes to script-output (flushed immediately, unlike the log)
local function progress(msg)
  helpers.write_file("rd-gui-progress.txt", msg .. "\n", true)
  log("[rd-gui-selftest] " .. msg)
end

local function shot(player, name)
  game.take_screenshot({
    player = player, path = name .. ".png", show_gui = true, show_entity_info = false,
    resolution = { 1600, 1000 }, zoom = 1, position = player.position,
    allow_in_replay = true, anti_alias = false,
  })
  progress("screenshot " .. name)
end

steps[#steps + 1] = function(player)
  -- some state to look at: a bit of history, research in progress, an archive
  local f = player.force
  for _, n in ipairs({ "automation", "logistics", "steel-processing", "military", "logistic-science-pack", "fast-inserter",
                       "turrets", "heavy-armor", "engine", "chemical-science-pack" }) do
    local t = f.technologies[n]
    if t then t.researched = true end
  end
  f.technologies["rd-archive"].researched = true
  local e = player.surface.create_entity({ name = "rd-archive", position = { player.position.x + 4, player.position.y }, force = f, raise_built = true })
  e.get_inventory(defines.inventory.chest).insert({ name = "processing-unit", count = 40 })
  f.research_queue = { "rd-consolidation-blue" }
  f.research_progress = 0.42
  remote.call("research-debt", "trade_lab", f.name)
  remote.call("research-debt", "new_request")
  player.zoom = 1.0
end
steps[#steps + 1] = function(player) remote.call("research-debt", "open_gui", player.index) end
steps[#steps + 1] = function(player) shot(player, "rd-gui-1-main") end
steps[#steps + 1] = function(player)
  -- scroll the archive request into view
  local function find(el, name)
    if el.name == name then return el end
    for _, c in pairs(el.children) do local f = find(c, name) if f then return f end end
  end
  local w = player.gui.screen["rd-main"]
  local req = find(w, "rd-request")
  if req then w.content.scroll.scroll_to_element(req, "top-third") end
  progress("request label found = " .. tostring(req ~= nil))
end
steps[#steps + 1] = function(player) shot(player, "rd-gui-6-request") end
local function window_alive(player)
  return player.gui.screen["rd-main"] ~= nil and player.gui.screen["rd-main"].valid
end
steps[#steps + 1] = function(player)
  remote.call("research-debt", "gui_toggle", player.index, "values")
  progress("after values toggle: window alive = " .. tostring(window_alive(player)))
end
steps[#steps + 1] = function(player) shot(player, "rd-gui-2-values") end
steps[#steps + 1] = function(player)
  remote.call("research-debt", "gui_toggle", player.index, "values")
  remote.call("research-debt", "gui_toggle", player.index, "log")
  progress("after log toggle: window alive = " .. tostring(window_alive(player)))
end
steps[#steps + 1] = function(player) shot(player, "rd-gui-2b-log") end
steps[#steps + 1] = function(player)
  -- scroll to the bottom, then force a refresh through a debt change: the position must survive
  local scroll = player.gui.screen["rd-main"].content.scroll
  scroll.scroll_to_bottom()
  progress("scrolled to bottom")
end
steps[#steps + 1] = function(player)
  remote.call("research-debt", "add_debt", 0.1, "selftest")
  progress("after refresh: scroll pane valid = " .. tostring(player.gui.screen["rd-main"].content.scroll.valid))
  storage.trace_until = game.tick + 100
end
steps[#steps + 1] = function(player) shot(player, "rd-gui-4-scrolled-after-refresh") end
steps[#steps + 1] = function(player)
  -- lab GUI with the relative panel
  remote.call("research-debt", "gui_toggle", player.index, "log")
  player.gui.screen["rd-main"].destroy()
  local lab = player.surface.create_entity({ name = "lab", position = { player.position.x - 4, player.position.y }, force = player.force })
  player.opened = lab
end
steps[#steps + 1] = function(player) shot(player, "rd-gui-5-lab") end
-- (the vanilla technology screen is not captured by take_screenshot, so it is not part of the self-test)
steps[#steps + 1] = function(player)
  player.opened = nil
  remote.call("research-debt", "reset")
  remote.call("research-debt", "open_gui", player.index)
end
steps[#steps + 1] = function(player) shot(player, "rd-gui-3-zero-debt") end
steps[#steps + 1] = function(player)
  progress("DONE")
  game.print("[rd-gui-selftest] DONE")
end

script.on_event(defines.events.on_tick, function(event)
  local player = game.get_player(1)
  if not player then return end
  if storage.trace_until and event.tick <= storage.trace_until and event.tick % 10 == 0 then
    progress("tick " .. event.tick .. " alive")
  end
  if not started then
    started = event.tick + 120
    progress("player present at tick " .. event.tick)
    return
  end
  local idx = math.floor((event.tick - started) / 90) + 1
  if event.tick >= started and (event.tick - started) % 90 == 0 and steps[idx] then
    progress("step " .. idx)
    local ok, err = pcall(steps[idx], player)
    if not ok then
      progress("STEP " .. idx .. " ERROR: " .. tostring(err))
      game.print("[rd-gui-selftest] ERROR: " .. tostring(err))
    end
  end
end)
