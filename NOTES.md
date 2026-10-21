# NOTES – verified API behaviour (Factorio 2.1.23, Steam, Space Age)

Everything below was checked against the bundled docs (`Factorio/doc-html/runtime-api.json`,
`prototype-api.json`) and/or observed on a real headless server through RCON (`tests/run.py`).

## Environment

- Install: `C:\Program Files (x86)\Steam\steamapps\common\Factorio` (Steam build 2.1.23, build 87750).
  The Steam client binary runs headless with `--create` / `--start-server` without Steam interaction.
- Space Age, Quality, Elevated Rails and Recycler are present as built-in mods in `data/`.
- Test environment lives in `%LOCALAPPDATA%\Temp\rd-test` (config, mods, saves, log) via `-c config.ini`
  with `write-data` pointing there. The user's own `%APPDATA%\Factorio` is never touched.
  The session folder itself could not be used: its path is too long for Factorio's scenario file copy.
- `info.json` needs `"factorio_version": "2.1"`. A mod declaring `2.0` is refused on 2.1
  ("Incompatible Factorio version"). The mod therefore targets 2.1 only.
- The server auto-pauses with no players by default; `server-settings.json` with `auto_pause: false`
  is required so that `on_nth_tick` fires in tests.
- RCON accepts connections slightly before the map finishes loading; the runner waits until
  `/silent-command rcon.print('ready')` answers.

## Multiplier

- `game.difficulty_settings.technology_price_multiplier` is read/write at runtime, range **0.001 – 100000**
  (the handoff said 1000; the 2.1 docs say 100000). The mod clamps to this range and to its own settings.
- `LuaTechnology.research_unit_count` reflects the new multiplier immediately (observed: 100 → 135 at ×1.35).
- **Running research**: when the multiplier changes mid-research, the completed *units* are preserved and
  `research_progress` is rescaled. Observed: progress 0.500 at 135 units → 0.287 at 235 units
  (67.5 units done either way). Nothing is lost; the remaining fraction simply grows.
- `settings.global[...]` can only be written by the owning mod ("Settings can only be changed by the
  owning player or the mod that made the setting"). Tests use `remote.call("research-debt","set_setting",...)`.
  A watchdog every 60 ticks re-applies the multiplier if anything else wrote it (verified: an external
  write of 7 is corrected within a second).

## Technologies

- `LuaTechnologyPrototype.max_level` is `4294967295` (uint32 max) for `max_level = "infinite"`.
  `research_unit_count_formula` is only set for formula-based techs. The mod uses the `max_level` check.
- `ignore_tech_cost_multiplier` works for infinite techs (fixed in 1.1.x per changelog). Verified:
  `mining-productivity-3` (infinite with Space Age) stays at 1000 units at ×1.35.
- Vanilla already sets `ignore_tech_cost_multiplier = true` on `automation`. It still *counts* for debt
  (default behaviour: counted, but not made more expensive itself).
- `data-final-fixes.lua` marked 23 infinite technologies with Space Age, 9 without.
- Space Age renames: `mining-productivity-3` is the infinite one (no `mining-productivity-4`).
- Trigger technologies (no science cost): in 2.x `electronics`, `steam-power`, `automation-science-pack`,
  `steel-axe`, `oil-processing` (with Space Age) and many planet techs use `research_trigger`.
  They are excluded by default (`rd-count-trigger-techs`).
- `on_research_finished` has `by_script`; scripted `tech.researched = true` fires it. The mod counts scripted
  research like normal research (consistent with the recalculation on an existing save).
- `on_research_reversed` exists (with `by_script`) and fires on `tech.researched = false`.
- `LuaTechnology.successors` / `prerequisites` are dictionaries of LuaTechnology; used for "forget".
- `on_configuration_changed` with `mod_changes["research-debt"].old_version == nil` identifies the mod being
  added to an existing save. Debt is then derived from every researched, counting tech of every force.

## Archive

- `LuaInventory.get_contents()` returns `{name, count, quality}` records in 2.x.
- `inventory.remove({name, count, quality})` removes exactly that quality.
- `prototypes.quality[name].level`: normal 0, uncommon 1, rare 2, epic 3, legendary 5.
- `flying-text` entities no longer exist; `rendering.draw_text` with `time_to_live` is used instead.
- `create_entity{raise_built=true}` raises `script_raised_built`, which the mod listens to.
- Only one `on_nth_tick(60)` handler per mod is possible; control.lua owns it and calls into modules.

## Trades

- `LuaForce.laboratory_speed_modifier` is read/write. Research-speed technologies add to it, and
  `reset_technology_effects()` recomputes it from scratch, so the mod re-applies its penalty in
  `on_technology_effects_reset`. Verified in tests.
- Evolution is per surface in 2.x: `force.get_evolution_factor(surface)` / `set_evolution_factor(f, surface)`.
  The GUI trades against the player's current surface.

## Design decisions

- Debt is one continuous number. Linear: `mult = base × (1 + debt)`. Exponential: `mult = base × (1+step)^(debt/step)`,
  i.e. every technology multiplies the cost by `(1+step)`. Both modes read the same `storage.debt`, so
  archive/consolidation reductions work identically in both.
- `storage.base_multiplier` is stored once at init (the map setting). If it is not 1 a warning is logged.
- The mod's own technologies (`rd-*`) never count and ignore the multiplier.
- Statistics (`storage.stats`) and a 30-entry history (`storage.history`) exist only to explain the state
  in the GUI; `storage.debt` is the single source of truth.

## Known limitations

- The multiplier is global; in PvP every force's research raises it for everyone. Lab-speed trades are per force.
- Startup settings cannot be set from the test runner (they live in binary `mod-settings.dat`), so tests run
  with default startup settings only.
- The GUI cannot be exercised headless (no players on a dedicated server). Test it in the client:
  see README "Manual GUI check".

## GUI (verified in the real client via tests/gui_check.py)

- Valid label styles in 2.1 include `heading_2_label`, `caption_label`, `bold_label`, `info_label`;
  `heading_1_label` does **not** exist (crashed the game from the tick handler until caught).
- A `frame` has no `vertical_spacing`; put a `flow` inside it. The window uses `naked_scroll_pane`
  with `maximal_height = 82%` of `player.display_resolution.height / display_scale`.
- `string.gsub` returns two values; a `fmt_int` that ended in `gsub` leaked the match count into the
  next argument of `LuaGuiElement.add` ("Unknown style 0"). Always wrap such returns in parentheses.
- GUI building runs under `xpcall(..., debug.traceback)`: an error closes the window, logs the trace
  and prints one chat line instead of crashing the game.
- Running the Steam build directly makes it relaunch itself through Steam: the spawned process exits
  with 0 immediately and the real client is a child of Steam. `tests/gui_check.py` therefore polls a
  progress file written with `helpers.write_file` (flushed at once, unlike the log) and kills leftover
  clients by command line.
- `game.take_screenshot{show_gui=true}` works from a mod in the client and lands in `script-output/`.

## GUI follow-up (user feedback, 2026-10-21)

- The window rebuilt its whole content every 60 ticks and on every debt change, which reset the scroll
  position. Now the scroll pane is created once; refreshes only rebuild the flow inside it (verified:
  scrolled to the bottom, debt changed, still at the bottom). The periodic tick only updates the
  consolidation status label in place.
- No `defines.relative_gui_type` exists for the technology screen or the research queue, so mods cannot
  draw there. The only research-related anchor is `lab_gui`; a panel with the multiplier, debt and a
  Details button is attached to it.
- HUD button: `rd-show-hud` now defaults to off, plus a checkbox at the bottom of the window. Players who
  already had the mod keep their stored value (true) until they untick it.

## Tiers and debt-free bonus (2026-10-21)

- Tier = highest known science pack in `research_unit_ingredients`; unknown (modded) packs fall back to
  the number of distinct packs. `Debt.step_for(proto)` is now used everywhere a step is added, removed,
  recalculated or shown, so reversing/forgetting always gives back exactly what the tech added.
- The bonus is an additive `laboratory_speed_modifier` tracked per force in `storage.bonus_applied`, like the
  lab trade penalty. Both are re-applied from one central `on_technology_effects_reset` handler in
  control.lua (a mod can register only one handler per event).
- Interest/decay (idea 3) was deliberately left out: the user does not want a runaway spiral.

## Archive requests (2026-10-21)

- Candidates = items in `Values.items` for which some research-enabled force has an enabled recipe producing
  them (`prototypes.recipe[...].products` × `force.recipes[name].enabled`). End products like spidertron are
  therefore only requested once unlocked.
- One global request in `storage.request`; `Requests.deliver(name, count)` is called from `Archive.process`
  and returns how many items get the bonus. Completion schedules the next request one interval later;
  expiry replaces it immediately (counted in `stats.requests_expired`).
- Uses `math.random`, which is deterministic in Factorio (multiplayer-safe).

- Upcoming requests: `storage.request_queue` always holds `request_queue_size` (3) entries drawn from the
  craftable candidates, preferring items not already current/queued. When a request ends, the head is
  promoted (skipped if no longer craftable) and the queue is refilled.
- Observed once in the client self-test: calling `scroll_to_bottom()` and rebuilding the scroll pane
  content in the same tick froze the client (no log, no crash). The mod never does that itself (players
  scroll with the mouse); the self-test now does the two in separate ticks.

## Factorio 2.0 (stable) support (2026-10-21)

- 2.1 is the experimental line, 2.0.77 the stable one. A mod zip serves exactly one line (`factorio_version`),
  so `build.py --factorio 2.0` writes a second zip with `factorio_version = "2.0"` and `base >= 2.0` from the
  same source; nothing else differs. Every API the mod uses exists in the 2.0.77 docs.
- Tested on 2.0.77 with the free Linux headless server inside WSL (`~/factorio-2.0/factorio`, includes
  space-age, quality and elevated-rails; the recycler mod only exists from 2.1):
  `wsl python3 tests/run.py --factorio ~/factorio-2.0/factorio/bin/x64/factorio --env /tmp/rd-test-2.0 --line 2.0`
  → 136/136, identical to 2.1.23.
- The runner now sets `read-data=__PATH__executable__/../../data`; `__PATH__system-read-data__` points to
  /usr/share/factorio on Linux.
