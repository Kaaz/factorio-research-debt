# Mod portal upload – copy/paste texts

Upload `dist/research-debt_0.1.0.zip` at https://mods.factorio.com/upload. The portal reads name,
title, version, Factorio version and dependencies from `info.json`; the fields below are the ones
you fill in by hand on the mod's edit page.

## Title

Research Debt

## Summary (short, shown in listings)

Research gets more expensive the more you research. Pay the debt off again with a special infinite
tech, by feeding stuff to an Archive, or by giving something else up (slower labs, higher evolution,
a tech you don't need anymore). Infinite techs are left alone. Works with and without Space Age.

## Category

Tweaks

## Tags

Technology, Manufacturing, Storage

## License

MIT

## Source / homepage

https://github.com/Kaaz/factorio-research-debt

## Description (Markdown)

I always felt that research in Factorio is a bit of a no-brainer: you queue up everything, you build
more labs, done. This mod makes you think about it. Every technology you finish adds "debt", and the
research cost multiplier of the map follows that debt. So after 40 techs everything costs roughly
twice as much, after 80 three times, and so on. Infinite techs (mining productivity, damage upgrades,
the Space Age productivity ones) don't care about any of this, they cost what they always cost and
don't add debt either.

The point is that you can pay the debt off, and every way of doing that costs you something else.

**Knowledge Consolidation** is an infinite research that removes a chunk of debt per level. The
multiplier doesn't touch it, but every level is 1.5x the price of the last one, so you can't just
spam it forever.

**The Archive** is a chest. Put valuable stuff in it (circuits, engines, LDS, rocket fuel, science
packs if you really want, the Space Age intermediates...) and it eats them and lowers the debt.
Better quality is worth more. The catch: the more you have archived over the whole game, the less
every item is worth, so it's not a free dump for your overflow. Every 15 minutes it also asks for a
specific item you can currently craft and pays triple for that one. The next three requests are
visible so you can set up production ahead of time.

**Trades.** Make your labs 10% slower for a bit of debt (you can undo that again). Raise the
evolution factor on your current planet (you can't undo that). Or forget a technology that nothing
else depends on: you lose the recipes, you get its debt back.

And if you ever get the debt down to zero, your labs run 20% faster until the next tech ruins it.

Ctrl+K opens a window that explains all of this in game: the current multiplier and where it comes
from, how much each option would lower it, buttons for the trades, and a log of what happened.
Opening a lab shows a small panel with the same numbers. There's an optional button at the top of
the screen too, off by default because I found it annoying.

Some things worth knowing:

- Red-only techs add half a step of debt, blue 1.5, purple/yellow 2, planet science 2.5, cryogenic 3,
  promethium 4. Can be turned off if you want every tech to count the same.
- Adding it to an existing save works, the debt is calculated from what you already researched. Don't
  panic when you open the save and see x7, that's what you'd have had anyway. `/rd-reset` zeroes it
  if you'd rather start fresh.
- Running research keeps its progress when the multiplier changes, only the remaining part grows.
- The multiplier is global, so in multiplayer every force pays for every force's research. I haven't
  played it in multiplayer yet, I'd like to hear how that goes.
- Won't play nice with other mods that also set the technology price multiplier.
- Pretty much every number is a setting, and the item values are in a plain Lua table if you want
  to tune them.
- Commands: /rd-status, /rd-recalc, /rd-reset, /rd-gui. There's a remote interface for mod authors.
- English and Dutch.

The balance is a first attempt based on my own games. If something feels off, too steep, too easy,
a trade that's never worth it, let me know in the discussion.

## FAQ

**Does it make infinite research more expensive?**
No. They ignore the multiplier and don't add debt.

**I added the mod to my existing save and research is suddenly x7.**
That's the debt for everything you already researched. Either pay it down, lower the maximum
multiplier in the map settings, or /rd-reset (admin) to start at zero.

**The multiplier went up while something was researching. Did I lose progress?**
No. Units already researched stay, only the remaining part gets bigger.

**Can you show the multiplier in the technology screen?**
I'd love to, but mods can't put anything there. The tech screen does show the increased unit counts
already. The why is in the Ctrl+K window and in the lab GUI.

**Multiplayer / PvP?**
One global multiplier for everybody. Lab trades, requests and the debt-free bonus are per force.
Untested in real multiplayer so far.

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
