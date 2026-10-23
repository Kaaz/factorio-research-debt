I always felt that research in Factorio is a bit of a no-brainer: you queue up everything, you build
more labs, done. This mod makes research something you have to manage, like power or ore patches.

## How a game goes

**You start normally.** Nothing is different until you finish your first technology. Then a chat line
tells you that it added a little debt and that research now costs x1.05. The next one makes it x1.10,
and so on. Red-only techs are cheap, green ones add twice as much, blue three times, and it keeps
climbing through the tiers up to promethium. The cost of every technology in the tree, the one you are
researching right now included, is multiplied by that number.

**It adds up faster than you think.** If you just keep queueing like you always did, the red and green
part of the tree alone leaves you at roughly x8 by the time you want blue science, and you'd reach the
rocket at something like x23. Every tech still works and still finishes, it just eats a lot more science.
So at some point, usually around the first time a tech costs more than your labs can chew through in a
reasonable time, you open the Research Debt window (Ctrl+K) and look at the options.

**You pay some of it back.** There are a few ways, and each one costs you something else:

- **Knowledge Consolidation**, a research in four tiers that follow your science packs: red+green,
  +blue, +purple/yellow, +space science. The first three have a limited number of levels (8, 10, 12),
  the last one is infinite, and unlocking the next tier replaces the previous one. Every level takes a
  share off the current debt (10% to 25% depending on the tier, at least 0.25), so it's the thing to do
  when the debt is big, and it never quite gets you to zero on its own. The multiplier doesn't apply to
  it, but each level costs 1.2x the previous one. Every level also gives a permanent 1% lab
  productivity, listed right in the tech screen.
- **The Archive**, a chest you unlock early. Anything with research value you put in it (circuits,
  engines, LDS, rocket fuel, the Space Age intermediates, science packs if you really want) gets eaten
  once per second and lowers the debt. Higher quality is worth more. The more you have archived over the
  whole game, the less every next item is worth, so it's not a free dump for your overflow. Every 15
  minutes the Archive also asks for a specific item you can craft right now and pays triple for it; the
  next three requests are shown in advance, so you can set up a little production line for them.
- **Trades.** Slow your labs down by 10% per step for a bit of debt (and buy the speed back later at
  the same price). Raise enemy evolution on the planet you are on (no way back). Forget a technology
  nothing else depends on: you lose its recipes and bonuses, you get its debt back.

**And then you research again.** That's the loop: research a batch, feel the price climb, decide what to
give up to bring it down, research the next batch. The only thing that is never touched are the
infinite technologies (mining productivity, damage upgrades, the productivity researches): they cost
what they always cost and don't add any debt, so your late game isn't ruined by this.

**Your labs feel it too.** At zero debt every lab runs 20% faster, below 0.5 still 10%, below 1.0 5%.
Let it climb above 3.0 and they slow down by 10%, above 5.0 by 20%, until you pay some back.

**Pick a preset.** Relaxed, Standard or Hardcore set all the numbers at once (step per tech, consolidation
cost, Archive, requests, the lab curve, the cap). Standard is tuned for people who have a few hundred hours
in the game. Custom unlocks the individual settings.

## Keeping track

The Research Debt window (Ctrl+K, or the button in the shortcut bar) always tells you where you stand:
the current multiplier and the formula behind it, where the debt came from, what the next technology
will do, and one card per way to lower it with live status and the buttons to do it. Opening any lab
shows a small panel with the same numbers. There's an optional button at the top of the screen too, off
by default because I found it annoying. Every change also goes to chat, which you can switch off.

## Good to know

- Adding the mod to an existing save works: the debt is calculated from what you already researched.
  Don't panic when you see x7, that is what you'd have had anyway. `/rd-reset` zeroes it if you'd rather
  start fresh, and the maximum multiplier is a map setting.
- Research in progress keeps its progress when the multiplier changes, only the remaining part grows.
- The multiplier is global. In multiplayer every force pays for every force's research; lab trades,
  requests and the bonus are per force. I haven't played it in multiplayer yet, I'd like to hear how
  that goes.
- Won't play nice with other mods that also set the technology price multiplier.
- With the Custom preset pretty much every number is a setting: debt per tech, tier scaling, limits, the
  lab curve, the request interval. The item values are in a plain Lua table if you want to tune them.
- Commands: /rd-status, /rd-recalc, /rd-reset, /rd-gui. There's a remote interface for mod authors.
- English and Dutch.

The balance is a first attempt based on my own games. If something feels off, too steep, too easy, a
trade that's never worth it, let me know in the discussion.
