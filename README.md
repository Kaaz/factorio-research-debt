# Research Debt

A Factorio 2.1 mod that makes research cost something.

I always felt research in Factorio is a bit of a no-brainer: queue everything, build more labs,
done. With this mod research has a cost that fits the engineer: *technical debt*. Every technology
you rush through leaves undocumented prototypes and half-tested recipes behind, your labs work
around the mess, and research gets more expensive until you clean up.

A game goes like this. You start normally; the first technology you finish adds a little *debt* and
research now costs ×1.05, the next one ×1.10, and so on, more per tech the higher its science tier.
If you keep queueing like before, the red and green part of the tree alone leaves you at roughly ×8,
and the rocket would come at about ×23. So at some point you open the window (Ctrl+K) and pay some of
it back: an infinite research that gets pricier per level, an Archive that eats valuable items (and
asks for specific ones at triple value), or trades: slower labs, higher evolution, forgetting a tech.
Then you research the next batch. Infinite technologies are never touched; your labs run faster while the
debt is low and slower while it is high. Works with and without Space Age. Factorio 2.1.

Zip: `python build.py` builds `dist/research-debt_<version>.zip`. Or copy the
`research-debt` folder into your mods folder as `research-debt_<version>`.

## How it works

One number, `storage.debt`, never below zero. Linear mode (default): multiplier = base × (1 + debt).
Exponential mode: every tech multiplies the cost by (1 + step). The result is clamped to the limits
from the map settings and to what Factorio allows (0.001 to 100000). `base` is whatever the map's
technology price multiplier was when the mod first loaded in that save, so a map that started at ×2
stays ×2 at zero debt.

Every change goes through one function (`Debt.add`) that writes a line to `factorio-current.log`:
`debt a -> b (+d) reason=... | multiplier x -> y`. Handy when something looks off.

### What adds debt

A technology adds `step × tier factor`, step being 0.1 by default. The tier is the highest science
pack the tech needs:

| Tier | Packs | Factor | Debt at step 0.1 |
|---|---|---|---|
| 1 | automation | 0.5 | 0.05 |
| 2 | logistic, military | 1.0 | 0.10 |
| 3 | chemical | 1.5 | 0.15 |
| 4 | production, utility | 2.0 | 0.20 |
| 5 | space, metallurgic, electromagnetic, agricultural | 2.5 | 0.25 |
| 6 | cryogenic | 3.0 | 0.30 |
| 7 | promethium | 4.0 | 0.40 |

Packs from other mods fall back to "number of different packs" as the tier. Tier scaling can be
switched off, then every tech is one step. Infinite techs, trigger techs (no science packs, unless
you enable them) and this mod's own techs add nothing. Research done by script counts like normal
research, which is also what the recalculation uses when you add the mod to an existing save.

### What removes debt

**Knowledge Consolidation.** Four tiers that follow the science packs: I (red+green, 8 levels, 10%
of the debt per level), II (+blue, 10 levels, 15%), III (+purple+yellow, 12 levels, 20%) and IV (+space
science, infinite, 25%). Only the highest tier you have unlocked can be researched; unlocking the next
one replaces it. Each level removes that share of the current debt, at least 0.25, so consolidation
brings a big debt down fast and can never do the last stretch to zero on its own. The multiplier doesn't
touch it, but every level costs 1.2× the previous one (bases 500 / 1000 / 2000 / 4000 units at 45 s; the last
level of III is about 15 000).
A reversed level gives back exactly what it removed, and levels of all tiers count together for the
milestones.

**The Reference Archive.** A chest with its own cheap tech. Items with a value in `scripts/values.lua` are
eaten once per second and lower the debt; the rest stays in the chest. Quality counts
(uncommon ×1.6 up to legendary ×4). Diminishing returns: the value of every extra point is
`1 / (1 + total points ever archived / 1000)`, so the Archive is never a free dump for overflow.
Science packs are deliberately cheap so that sacrificing science is never the smart route.

Every 15 minutes the Archive requests a specific item you can currently craft and pays 3× for the
requested amount. The next three requests are shown in advance so you can set up production. A
fulfilled request schedules the next one, an expired one is replaced on the spot, and queued items
that became uncraftable (you forgot the tech) are skipped.

**Trades.** Make your force's labs 10% slower for 0.25 debt, at most five times, reversible at the
same rate. Raise enemy evolution on your current surface by 5% for 0.25 debt, not reversible, not
available at 95%+. Or forget a technology nothing else depends on: you lose its recipes and bonuses
and get back exactly the debt it added.

**Lab speed follows the debt.** At zero debt all labs run 20% faster, below 0.5 10%, below 1.0 5%.
Above 3.0 they run 10% slower, above 5.0 20% slower, until you pay some back. Every level of
Knowledge Consolidation adds a permanent 1% lab productivity, as a regular technology effect.

**Presets.** Relaxed, Standard (tuned for experienced players) and Hardcore set the step, the
consolidation cost and value, the Archive half-life, the request interval, the lab curve and the
maximum multiplier together; Custom uses the individual settings. Tables in `scripts/config.lua`.

All the numbers live in `scripts/config.lua` (presets), `settings.lua` (Custom), `scripts/values.lua`
(`Values.Balance`, `Values.items`), `scripts/tiers.lua` and `scripts/trades.lua`.

## In game

- **Ctrl+K** (or the shortcut bar button, or `/rd-gui`): the window. Current multiplier with the
  formula behind it, what the next tech will do, a breakdown of where the debt came from, the tier
  table, one card per way to lower it with live status and buttons, what is never affected, and
  the last 8 changes.
- **Lab panel**: open any lab and a small panel shows the multiplier, the debt and a Details
  button. The technology screen and the research queue can't be extended by mods, this is the
  closest I could get.
- **HUD button** at the top, off by default (it got on my nerves). Checkbox at the bottom of the
  window or the per-player setting.
- Chat messages on every debt change, can be turned off.

## Commands

```
/rd-status            debt, base, multiplier, limits, counters
/rd-recalc            (admin) recount researched technologies and archives
/rd-reset             (admin) debt to zero, trades undone
/rd-gui               open/close the window
```

For mod authors there's `remote.call("research-debt", ...)` with `status()`, `add_debt(x, reason)`,
`reset()`, `recalculate()`, `set_base(x)`, `counts(tech)`, `step_for(tech)`, `history()`,
`archive_value(item, quality)`, `balance()`, the trades (`trade_lab`, `trade_lab_undo`,
`trade_evolution`, `forgettable`, `forget`, `trades_state`), the requests (`request`,
`request_queue`, `new_request`) and `open_gui(player_index)`. See `control.lua`.

## Good to know

- The multiplier is global. In PvP every force's research raises it for everyone. Lab trades,
  requests and the bonus are per force where that makes sense. I haven't played it in multiplayer
  yet.
- Other mods that also write `technology_price_multiplier` won't get along with this one. The mod
  warns in the log when the map's base multiplier isn't 1 and re-applies its own value every second.
- Infinite techs from other mods are picked up automatically in `data-final-fixes.lua`.
- Research that is running keeps its finished units when the multiplier changes; only the rest grows.
- Adding the mod to an existing save: the debt is calculated from everything already researched.

## Developing and releasing

See [DEVELOPMENT.md](DEVELOPMENT.md) for setup, testing on 2.1 and 2.0, the release workflow and the portal
page, and [NOTES.md](NOTES.md) for verified API behaviour and design decisions.

## Repository layout

```
research-debt/            the mod
  settings.lua            startup, map and per-player settings
  data.lua                Knowledge Consolidation, Archive entity/item/recipe/tech, shortcut, hotkey
  data-final-fixes.lua    ignore_tech_cost_multiplier on every infinite tech
  control.lua             events, commands, remote interface
  scripts/debt.lua        the model (the only place that writes the multiplier)
  scripts/tiers.lua       science tiers
  scripts/values.lua      Archive balance table
  scripts/archive.lua     Archive tracking and processing
  scripts/requests.lua    Archive requests
  scripts/trades.lua      lab speed / evolution / forget
  scripts/config.lua      presets and resolved balance values
  scripts/bonus.lua       lab speed curve and consolidation milestones
  scripts/gui.lua         window, HUD, lab panel
  locale/en, locale/nl
tests/                    see below
build.py                  builds dist/research-debt_<version>.zip
NOTES.md                  what I verified against the API and why things are the way they are
PORTAL.md                 how the mod portal page is maintained
DEVELOPMENT.md            setup, tests, release process
CLAUDE.md                 conventions for AI-assisted sessions
```

## Tests

```bash
python tests/run.py
```

Spins up a real headless Factorio server in `%LOCALAPPDATA%\Temp\rd-test` (own config, mods and
saves, your `%APPDATA%\Factorio` is not touched), talks to it over RCON and runs about 135 checks:
the multiplier going up, infinite techs being immune, reversing, clamps, recalculation, research in
progress, consolidation, the Archive with quality and diminishing returns, requests, trades, tiers,
the bonus, save/restart, adding the mod to an existing save, and most of it again without Space Age.
Uses the Steam build directly, so Steam may show you as playing. Options: `--no-space-age`,
`--only phase1 trades ...`, `--env PATH`, `--factorio PATH`.

```bash
python tests/gui_check.py
```

Starts the actual client (windowed, English) on a throwaway save with a tiny helper mod that opens
the window, expands things, scrolls, opens a lab and takes screenshots into
`%LOCALAPPDATA%\Temp\rd-test-gui\data\script-output`. A Factorio window pops up for about half a
minute. `tests/portal_images.ps1` crops those into the images for the portal page.

To poke at it by hand on the test save:

```bash
"/c/Program Files (x86)/Steam/steamapps/common/Factorio/bin/x64/factorio.exe" -c "$LOCALAPPDATA/Temp/rd-test/config/config.ini" --mod-directory "$LOCALAPPDATA/Temp/rd-test/data/mods" --load-game "$LOCALAPPDATA/Temp/rd-test/data/saves/test.zip"
```

## License

MIT, see [LICENSE](LICENSE).
