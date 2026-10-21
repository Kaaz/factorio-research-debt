# Research Debt (Kennisschuld) – Factorio 2.1 mod

Every non-infinite technology you research adds *debt*. The global technology price multiplier
follows the debt, so research gets more expensive the more you know. Infinite technologies are
never affected and never add debt. You pay debt back through a dedicated infinite research, by
sacrificing items in an Archive, or by trading something else you value (lab speed, enemy
evolution, a technology you no longer need). The in-game window (Ctrl+K) always shows why the
multiplier is what it is and what you can do about it.

Works with and without Space Age. Requires Factorio 2.1.

## Layout

```
research-debt/            the mod (copy or symlink into your mods folder as research-debt_0.1.0)
  info.json
  settings.lua            startup + map + per-player settings
  data.lua                Knowledge Consolidation tech, Archive entity/item/recipe/tech, shortcut + hotkey
  data-final-fixes.lua    ignore_tech_cost_multiplier on every infinite tech (any mod)
  control.lua             event wiring, commands, remote interface
  scripts/debt.lua        the model: storage.debt -> multiplier (single writer)
  scripts/values.lua      Archive balance table (item points, quality bonus, diminishing returns)
  scripts/archive.lua     Archive tracking and processing
  scripts/trades.lua      lab speed / evolution / forget trades
  scripts/gui.lua         Research Debt window + HUD
  locale/en, locale/nl
tests/run.py              end-to-end tests against a real headless server (RCON)
tests/phases.py           phase 2/3/trades tests
tests/rcon.py             tiny RCON client (no dependencies)
NOTES.md                  verified API behaviour and design decisions
```

## The model

```
debt      >= 0, one number in storage.debt
linear:      multiplier = base × (1 + debt)
exponential: multiplier = base × (1 + step) ^ (debt / step)
clamped to [base × rd-min-multiplier, rd-max-multiplier] and to Factorio's [0.001, 100000]
```

`base` is the map's technology price multiplier at the moment the mod is first loaded in that save.
Every change goes through one function (`Debt.add`) which logs `debt a -> b (+d) reason=... | multiplier x -> y`
to `factorio-current.log`.

### Science tiers (default on, `rd-tier-scaling`)

The highest science pack a technology needs sets its tier; the step is multiplied by the tier factor:

| Tier | Packs | Factor | Debt at step 0.1 |
|---|---|---|---|
| 1 | automation | 0.5 | 0.05 |
| 2 | logistic, military | 1.0 | 0.10 |
| 3 | chemical | 1.5 | 0.15 |
| 4 | production, utility | 2.0 | 0.20 |
| 5 | space, metallurgic, electromagnetic, agricultural | 2.5 | 0.25 |
| 6 | cryogenic | 3.0 | 0.30 |
| 7 | promethium | 4.0 | 0.40 |

Packs from other mods fall back to "number of distinct packs" as the tier. Table in `scripts/tiers.lua`.

### Debt-free bonus (`rd-debt-free-bonus`, default 0.2)

While the debt is exactly zero, every force gets +20% lab speed. Any technology that adds debt ends the
bonus until the debt is paid off again. The window, the HUD tooltip and the lab panel show the state.

### Archive requests (`rd-request-interval`, default 15 minutes)

Every interval the Archive asks for a specific item from the value table that some force can currently
craft (random, never the same twice in a row). Delivering the requested amount to any Archive counts at
3× value; items beyond the amount count normally. A fulfilled request schedules the next one an interval
later; an unfulfilled one is replaced when it expires. The archive card shows the request, progress, time
left and what the remaining delivery is worth, plus the next three requests so you can plan production.
Queued items that become uncraftable (forgotten technology) are skipped. 0 disables requests. Numbers in `Values.Balance`
(`request_bonus`, `request_points`, `request_min`, `request_max`).

### What adds debt

| Event | Debt |
|---|---|
| Finishing a non-infinite technology (any force; scripted research counts too) | `+step × tier factor` (step default 0.1) |
| Finishing a trigger technology (no science packs) | `+step` only if `rd-count-trigger-techs` is on |
| Finishing an infinite technology level | 0 |
| Finishing one of this mod's technologies | 0 |
| Undoing a lab-speed trade | `+0.25` |

### What removes debt

| Method | Effect | Trade-off |
|---|---|---|
| **Knowledge Consolidation** (infinite tech, needs chemical science) | `-0.25` per level | 500 × 1.5^(L-1) units of red/green/blue; never affected by the multiplier |
| **Archive** (chest, unlocked by its own cheap tech) | item points × quality × efficiency × 0.001 | items are destroyed; efficiency = 1 / (1 + total points ever archived / 1000) |
| **Slow labs** (per force, max 5 steps) | `-0.25` per 10% lab speed | reversible at the same rate |
| **Feed the enemy** (+5% evolution on your current surface) | `-0.25` | irreversible, unavailable at ≥95% evolution |
| **Forget a technology** nothing else depends on | `-step × its tier factor` | you lose its recipes/bonuses and must pay its full cost again |

All numbers are in one place: `settings.lua` (step, consolidation value, limits),
`scripts/values.lua` (`Values.Balance`, `Values.items`) and `scripts/trades.lua` (`Trades.Balance`).

## In-game UI

- **HUD** button at the top (off by default): `Research ×2.35` (orange while there is debt, green at base). Hover for the
  summary, click to open the window. Toggle with the checkbox at the bottom of the window or the per-player setting `rd-show-hud`.
- **Lab panel**: opening any lab shows a side panel with the current multiplier, the debt and a Details button.
  The technology screen and research queue cannot be extended by mods (no GUI anchor exists for them).
- **Window** (Ctrl+K, the shortcut-bar button, `/rd-gui`, or the HUD):
  1. the current multiplier, the formula that produces it, and what the next technology will do;
  2. *Why is it this high?* – a breakdown: technologies × step, consolidation, archive, trades, total;
  3. *How to lower it* – one card per method with live status (locked / available / in queue / researching …),
     concrete numbers ("one technology step ≈ 53 processing units right now"), and action buttons
     (queue consolidation, show the value table, slow/restore labs, feed the enemy, forget a technology);
  4. what is never affected;
  5. the last 8 changes with timestamps.
- Chat messages on every debt change (`rd-chat-notifications`).

## Commands and remote interface

```
/rd-status            debt, base, multiplier, limits, counters
/rd-recalc            (admin) recount researched technologies and archives
/rd-reset             (admin) debt to zero
/rd-gui               open/close the window
```

`remote.call("research-debt", ...)`: `status()`, `add_debt(x, reason)`, `reset()`, `recalculate()`,
`set_base(x)`, `counts(tech_name)`, `history()`, `archive_value(item, quality)`, `archive_preview(points)`,
`archive_process_now()`, `balance()`, `trade_lab(force)`, `trade_lab_undo(force)`,
`trade_evolution(force, surface_index)`, `forgettable(force)`, `forget(force, tech)`, `trades_state(force)`,
`open_gui(player_index)`.

## Compatibility notes

- The multiplier is global. In PvP every force's research raises it for all forces. Lab trades are per force.
- Other mods that write `technology_price_multiplier` are not supported; the mod logs a warning when the
  map's base multiplier is not 1 and re-applies its own value every second (watchdog).
- Infinite technologies from other mods are handled automatically in `data-final-fixes.lua`.
- Research in progress keeps its completed units when the multiplier changes; only the remaining fraction grows.
- Adding the mod to an existing save: debt = (researched, counting technologies of all forces) × step.

## Testing

```bash
python tests/run.py
```

Creates an isolated Factorio data folder in `%LOCALAPPDATA%\Temp\rd-test`, copies the mod there, creates a
save, starts a headless server with RCON and runs ~95 checks: phase 1 (rise, infinite immunity, reverse,
clamps, recalculation, running research), phase 2 (consolidation), phase 3 (archive incl. quality and
diminishing returns), trades, save/restart persistence, adding the mod to an existing save, and the same
again without Space Age. Options: `--no-space-age`, `--only phase1 phase2 ...`, `--env PATH`, `--factorio PATH`.

The Steam build of Factorio is used directly; Steam may briefly show you as "playing Factorio".
Your own saves, mods and settings in `%APPDATA%\Factorio` are not touched.

### Automated GUI check (opens the real client)

```bash
python tests/gui_check.py
```

Creates `%LOCALAPPDATA%\Temp\rd-test-gui`, adds the tiny helper mod from `tests/selftest-mod`, starts the
Factorio client windowed on a fresh save, opens the window, expands the value table and the log, takes
screenshots (`rd-test-gui/data/script-output/rd-gui-*.png`) and closes the client again. A Factorio window
appears on screen for about half a minute.

### Manual GUI check

The window cannot be tested headless. Start the client on the test save (same isolated config):

```bash
"/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" -c "$LOCALAPPDATA/Temp/rd-test/config/config.ini" --mod-directory "$LOCALAPPDATA/Temp/rd-test/data/mods" --load-game "$LOCALAPPDATA/Temp/rd-test/data/saves/test.zip"
```

Then press Ctrl+K, research something, build an Archive (`/c game.player.insert{name="rd-archive"}`) and watch
the window and HUD update.

## License

MIT, see [LICENSE](LICENSE). The same file ships inside the mod zip.
