**Why "debt"?**
Technical debt: the mess you leave behind when you rush things into production. Every technology adds
some, your labs work around it, research gets more expensive. Cleaning up is the game.

**Does it make infinite research more expensive?**
No. They ignore the multiplier and leave no debt.

**I added the mod to my existing save and research is suddenly many times the price.**
That's the debt for everything you already researched. Either clean it up, lower the maximum
multiplier in the map settings, or /rd-reset (admin) to start at zero.

**The multiplier went up while something was researching. Did I lose progress?**
No. Units already researched stay, only the remaining part gets bigger.

**Can you show the multiplier in the technology screen?**
Mods can't draw there, but the tech screen already shows the increased unit counts, and the Knowledge
Consolidation techs list their lab productivity bonus like any other technology. The why is in the
Ctrl+K window and in the lab GUI.

**Where are the exact numbers?**
In game: the Research Debt window shows every value for your current preset and debt. Outside: the
README on GitHub has the full tables.

**Can it break my save? How do I get rid of it?**
It changes the research cost multiplier, lab speed (through hidden technologies) and lab productivity (Knowledge
Consolidation levels), and, only when you choose to, enemy evolution, retired technologies and items in the archive. To remove it:
`/rd-uninstall`, save, remove the mod. Without that step the research cost multiplier stays at its last value;
add the mod again and run it, or `/rd-set-base 1` if you re-added it to such a save.

**Multiplayer / PvP?**
One global multiplier for everybody. Careful mode, requests and the lab speed curve are per force.
Untested in real multiplayer so far.
