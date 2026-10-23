I always felt that research in Factorio is a bit of a no-brainer: you queue up everything, you build
more labs, done. This mod gives research a cost that fits the engineer we all play: technical debt.

## The idea

You don't research carefully. You rush prototypes into production, leave recipes half tested, scribble
notes on whatever is at hand. Every technology you finish leaves some of that mess behind, and your
labs have to work around it. So the next research costs more science, and the one after that a bit
more again. Cheap red techs barely register; a blue tech leaves a noticeable pile; the late-game stuff
with planet science or promethium is a proper mountain. Every technology in the tree pays the same
multiplier, the one you are researching right now included.

Nothing breaks. It just adds up faster than you think: keep queueing like you always did and research
is several times its normal price by the time you want blue science, and by the rocket you would be
paying many times over for every technology. So at some point, usually the first time a tech takes
longer than you are willing to wait, you open the Research Debt window (Ctrl+K) and clean up.

## How you clean up

Each way costs you something else.

- **Knowledge Consolidation.** Your labs stop and tidy: documenting prototypes, testing recipes
  properly, sorting the notes. It comes in four tiers that follow your science packs; the early tiers
  have a handful of levels and get replaced by the next one when you unlock those packs, only the
  space-science tier goes on forever. Every level clears a share of whatever you owe right now, so it
  hits hard when the debt is big and does little for the last bit. Levels get pricier as you climb, but
  the multiplier never applies to this research, and every level you finish makes all your labs a bit
  more productive, permanently. It's listed in the tech screen like any other bonus.
- **The Reference Archive.** A chest you unlock early. Put working samples of your products in it
  (circuits, engines, LDS, rocket fuel, the Space Age intermediates, science packs if you really want)
  and they are filed away for good, so the labs can stop re-deriving them. Higher quality samples are
  worth more. The fuller the archive, the less each new sample is worth, so it's not a free dump for
  your overflow. Now and then the archive is missing a specific sample you can craft and pays a lot
  more for it; the next few requests are shown in advance, so you can set up a little production line.
- **Careful mode.** Let your labs double-check their work: a notch slower per step, a bit of debt
  cleared per step, and you can switch back at the same rate whenever you like.
- **Dump lab waste.** Get rid of the failed experiments the quick way. The biters on your current planet
  evolve on it, and there is no way back.
- **Retire a technology.** Throw out the documentation of a technology nothing else depends on: you lose
  its recipes and bonuses, you get its debt back.

**And then you research again.** That's the loop: research a batch, feel the price climb, decide what to
give up to clean up, research the next batch. The only things never touched are the infinite
technologies (mining productivity, damage upgrades, the productivity researches): they cost what they
always cost and leave no debt, so your late game isn't ruined by this.

**Your labs feel it too.** Keep the debt low and every lab runs faster, with the biggest boost when there
is none at all. Let it run away and they drown in undocumented work and slow down until you clean up.
The window always shows which step you are on and how much debt separates you from the next one.

**Pick a preset.** Relaxed, Standard or Hardcore set all the numbers at once. Standard is tuned for
people who have a few hundred hours in the game and want research to be a real decision; Relaxed takes
the edge off; Hardcore is for when you want to feel every tech. Custom unlocks the individual settings.

## Keeping track

The Research Debt window (Ctrl+K, or the button in the shortcut bar) always tells you where you stand:
the current multiplier and the formula behind it, where the debt came from, what the next technology
will leave behind, and one card per way to clean up with live status, the exact numbers and the buttons
to do it. Opening any lab shows a small panel with the same numbers. There's an optional button at the
top of the screen too, off by default because I found it annoying. Every change also goes to chat,
which you can switch off.

## Good to know

- Adding the mod to an existing save works: the debt is calculated from what you already researched.
  Don't panic when the multiplier opens high, that is what you'd have had anyway. `/rd-reset` zeroes it
  if you'd rather start fresh, and the maximum multiplier is a map setting.
- Research in progress keeps its progress when the multiplier changes, only the remaining part grows.
- The multiplier is global. In multiplayer every force pays for every force's research; careful mode,
  requests and the lab speed curve are per force. I haven't played it in multiplayer yet, I'd like to
  hear how that goes.
- Won't play nice with other mods that also set the technology price multiplier.
- With the Custom preset pretty much every number is a setting; the item values are in a plain Lua table
  if you want to tune them. The README on GitHub has all the exact numbers.
- Commands: /rd-status, /rd-recalc, /rd-reset, /rd-gui. There's a remote interface for mod authors.
- English and Dutch.

The balance is a first attempt based on my own games. If something feels off, too steep, too easy, a
trade that's never worth it, let me know in the discussion.
