# Mod portal upload – copy/paste texts

Upload `dist/research-debt_0.1.0.zip` at https://mods.factorio.com/upload. The portal reads name,
title, version, Factorio version and dependencies from `info.json`; the fields below are the ones
you fill in by hand on the mod's edit page.

## Title

Research Debt

## Summary (short, shown in listings)

Every technology you research makes the next one more expensive. Pay the debt back with a dedicated
infinite research, by sacrificing items in an Archive, or by trading lab speed, enemy evolution or a
technology you no longer need. Infinite techs are never affected. An in-game window always shows why
research costs what it costs and what you can do about it. Works with and without Space Age.

## Category

Tweaks (it changes research cost rules and adds a few supporting prototypes; not an overhaul)

## Tags

Technology, Manufacturing, Storage

## License

MIT

## Source / homepage

(GitHub URL once the repository exists)

## Description (Markdown)

**Research Debt** turns research into an economy. Every non-infinite technology you finish adds *debt*,
and the global technology price multiplier follows the debt: the more you know, the more the next
discovery costs. The debt can be paid back, so the question is no longer only *what* to research but
*when*, and what you are willing to give up for it.

### What raises the cost

- Every non-infinite technology adds debt, scaled by its science tier: red-only techs add 0.05,
  green 0.10, blue 0.15, purple/yellow 0.20, space and planet packs 0.25, cryogenic 0.30, promethium 0.40
  (all configurable).
- Linear mode (default): multiplier = base × (1 + debt). Exponential mode: every technology multiplies
  the cost by (1 + step).
- **Infinite technologies** (mining productivity, weapon damage, research productivity, from any mod)
  ignore the multiplier completely and never add debt.

### How to pay it back

- **Knowledge Consolidation** – an infinite research that removes debt. Immune to the multiplier,
  but every level costs 1.5× the previous one.
- **Archive** – a chest that permanently consumes valuable items (circuits, engines, science packs,
  Space Age intermediates…). Higher quality is worth more; the more you have archived in total, the
  less each item is worth. Every 15 minutes the Archive *requests* a specific craftable item at 3×
  value, and shows the next three requests so you can plan production.
- **Trades** – make your labs slower (reversible), raise enemy evolution on your current planet
  (not reversible), or forget a technology nothing else depends on.
- **Debt-free bonus** – while your debt is exactly zero, all labs run 20% faster.

### Always know why

Press **Ctrl+K** (or use the shortcut-bar button) for the Research Debt window: the current multiplier
and the formula behind it, a breakdown of where the debt came from, one card per way to lower it with
live status and action buttons, and a log of recent changes. Opening any lab shows a compact panel with
the same numbers. Optional HUD button at the top of the screen.

### Details

- Factorio 2.1, with or without Space Age / Quality.
- Adding the mod to an existing save recalculates the debt from the technologies already researched.
- Multiplayer: the multiplier is global, so every force's research raises it for everyone. Lab-speed
  trades are per force. Not yet tested in a real multiplayer session: feedback welcome.
- Not compatible with other mods that write the technology price multiplier.
- Everything is tunable: startup settings (step, growth mode, tier scaling, trigger techs, Archive,
  trades), map settings (max/min multiplier, debt-free bonus, request interval, chat messages) and
  one per-player setting (HUD). Balance tables live in `scripts/values.lua`, `scripts/tiers.lua` and
  `scripts/trades.lua`.
- Commands: `/rd-status`, `/rd-recalc`, `/rd-reset`, `/rd-gui`. Remote interface `research-debt`
  for other mods.
- Languages: English, Dutch.

### Feedback

Balance numbers are first guesses from a solo playtest. If the curve feels too steep or too flat,
or a trade is never worth it, say so: this mod lives on feedback.

## FAQ

**Does it make infinite research more expensive?**
No. Infinite technologies ignore the multiplier entirely and never add debt.

**I added the mod to my existing save and research is suddenly ×7.**
The debt was recalculated from everything you had already researched. Either accept it (your first
goal is now to pay it down), lower "Maximum research cost multiplier" in the map settings, or run
`/rd-reset` as admin to start at zero.

**The multiplier changed while a research was running. Did I lose progress?**
No. Finished research units are kept; only the remaining fraction grows.

**Can I see the multiplier in the technology screen?**
Factorio does not let mods draw there. The tech screen already shows the increased unit counts; the
*why* is in the Research Debt window (Ctrl+K) and the lab panel.

**What about multiplayer / PvP?**
The multiplier is global. All forces build debt and all forces pay the price. Lab trades, requests and
the debt-free bonus are per force where that makes sense.

## Images

- `research-debt/thumbnail.png` (144×144) ships inside the zip; the portal picks it up automatically.
- Gallery images: run `tests/gui_check.py` (English client screenshots) and then
  `powershell -File tests/portal_images.ps1`, which crops them into `dist/portal-images/`:
  1. `1-window-overview.png` – multiplier, breakdown, tier table, debt-free bonus
  2. `2-ways-to-lower-and-requests.png` – consolidation, archive with request and queue
  3. `3-archive-value-table.png` – value table expanded
  4. `4-trades-and-log.png` – lab/evolution/forget trades and the change log
  5. `5-lab-panel.png` – the panel attached to the lab GUI
  Upload them on the mod's edit page under "Images" in that order; the first one becomes the cover.

## Changelog

Paste `research-debt/changelog.txt` as is; the portal renders this format.
