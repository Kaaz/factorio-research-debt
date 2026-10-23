# Development guide

How this project is set up, tested and released. Read this before changing anything; NOTES.md has
the *why* behind the design and the API facts that were verified along the way.

## 1. Layout

```
research-debt/        the mod itself (this folder, and only this folder, ends up in the zip)
  info.json           name, version (2.1.x), factorio_version (2.1), dependencies
  settings.lua        startup / map / per-player settings
  data.lua            prototypes: Knowledge Consolidation, Archive, shortcut, hotkey
  data-final-fixes.lua  marks every infinite tech ignore_tech_cost_multiplier
  control.lua         event wiring, commands, remote interface
  scripts/debt.lua    the model; the only code that writes technology_price_multiplier
  scripts/tiers.lua   science tiers and their factors
  scripts/values.lua  Archive balance table and request balance
  scripts/archive.lua Archive registry and processing
  scripts/requests.lua Archive requests and the upcoming queue
  scripts/trades.lua  lab speed / evolution / forget trades
  scripts/bonus.lua   debt-free lab speed bonus
  scripts/gui.lua     window, HUD button, lab panel
  locale/en, locale/nl   one .cfg per feature; a section may not repeat inside one file
  changelog.txt       Factorio changelog format; the first "Version:" is the current one
  thumbnail.png       144x144, shown on the portal
portal/               texts and metadata for the portal page (summary, description, FAQ, meta.json)
tools/portal.py       mod portal API client (publish, upload, details, images, release)
tests/                headless test suite, client GUI check, screenshot tooling
build.py              builds the zips
PORTAL.md             how the portal page is maintained
NOTES.md              verified API behaviour, design decisions, findings
creds.txt             (git-ignored) "key=<portal API key>"; never commit, never print
```

## 2. Conventions

- Mod version = Factorio line + patch: 2.1.x for Factorio 2.1. Bump only the patch in `info.json`.
- Factorio 2.0 was served once (2.0.0, identical features) and is not updated anymore since 2.1 became stable.
  `build.py --factorio 2.0` and the WSL test run still exist should that ever be needed again.
- `storage.debt` is the single source of truth. Every change goes through `Debt.add(delta, reason, detail)`,
  which logs one line (`[research-debt] debt a -> b (+d) reason=...`) and refreshes the GUI. Never write
  `game.difficulty_settings.technology_price_multiplier` anywhere else.
- Per-tech amounts always come from `Debt.step_for(proto)` so reversing/forgetting returns exactly what was added.
- Balance numbers live in tables, not in logic: `settings.lua`, `Values.Balance` / `Values.items`,
  `Tiers.Balance`, `Trades.Balance`.
- Only one `on_nth_tick(60)` handler and one handler per event per mod: control.lua owns them and calls modules.
- GUI code runs under `xpcall`; an error closes the window and logs a traceback instead of crashing the game.
- All user-facing text goes through locale keys (English and Dutch). New keys go in the .cfg of the feature;
  add a new file rather than repeating a section in an existing one (Factorio rejects duplicates).
- Docs and portal texts are English, written in the author's own voice (see PORTAL.md and portal/).

## 3. Local setup

- Factorio 2.1 (Steam) at `C:\Program Files (x86)\Steam\steamapps\common\Factorio`. Its `doc-html/` folder has
  the API docs of the installed version (`runtime-api.json`, `prototype-api.json`); grep those first.
- Factorio 2.0.77 headless server in WSL (Ubuntu) at `~/factorio-2.0/factorio`, downloaded from
  https://factorio.com/get-download/stable/headless/linux64 (free, no account). Includes space-age, quality,
  elevated-rails; the recycler mod only exists on 2.1.
- Python 3 on Windows (with `requests`) and `python3` in WSL.
- To play with the current source: copy `research-debt/` to `%APPDATA%\Factorio\mods\research-debt_<version>`
  (folder name must match the version in info.json). Factorio must not be running while you copy.

## 4. Testing

Everything is tested against a real game, never mocked.

### Headless suite (logic)

```bash
python tests/run.py                              # Factorio 2.1 (Steam build), with and without Space Age
wsl python3 tests/run.py --factorio ~/factorio-2.0/factorio/bin/x64/factorio --env /tmp/rd-test-2.0 --line 2.0
```

Uses its own write-data folder (`%LOCALAPPDATA%\Temp\rd-test` or `/tmp/rd-test-2.0`): own config, mods, saves,
log. Your own Factorio data is never touched. It starts a headless server with RCON, drives it with
`/silent-command`, and checks about 136 things: multiplier rising, infinite techs immune, reversing, clamps,
recalculation, running research, consolidation, Archive (quality, diminishing returns, requests, queue),
trades, tiers, bonus, save/restart, adding the mod to an existing save, and the same without Space Age.
`--only phase1 phase2 phase3 trades tiers bonus requests persist existing nosa` selects parts.

Startup settings are tested at their defaults: they live in the binary `mod-settings.dat`, which the suite
deletes before a run so new defaults take effect. Runtime settings are changed through
`remote.call("research-debt","set_setting",name,value)` (only the owning mod may write them).

The 2.1 run must be green before a release; the 2.0 run only matters if a 2.0 release is made.

### Client check (GUI)

```bash
python tests/gui_check.py
```

Starts the real client windowed, in English, on a throwaway save with the helper mod `tests/selftest-mod`,
which opens the window, expands the value table and the log, scrolls, opens a lab and takes screenshots
into `%LOCALAPPDATA%\Temp\rd-test-gui\data\script-output`. A Factorio window appears for about half a minute.
Check the log for `GUI error` afterwards; the script prints the count. Copy the screenshots to
`tests/screenshots/` if you want to look at them later (that folder is git-ignored, 2.5 MB each).

### Playing

`/rd-status` prints the state, `/rd-recalc` recounts, `/rd-reset` zeroes the debt and undoes trades,
`/rd-gui` toggles the window. The log line per debt change is the easiest way to see what happened.

## 5. Releasing

1. Bump the patch in `research-debt/info.json` (e.g. 2.1.0 → 2.1.1) and add a block to `changelog.txt`
   with the new version on top. Keep the Factorio changelog format (the portal and the game render it).
2. Run both headless suites and the client check.
3. Commit, tag and push:

   ```bash
   git tag v2.1.1 && git push origin master v2.1.1
   ```

4. The workflow `.github/workflows/release.yml` then: checks that the tag matches `info.json`, runs
   `python build.py`, creates a GitHub release with the zip and the changelog block as notes, uploads the
   zip to the mod portal (a version already there is skipped) and pushes the texts from `portal/`. The portal steps run only when the repository secret `FACTORIO_API_KEY` is set
   (Settings → Secrets and variables → Actions). Create the key at https://factorio.com/profile with the
   usages "ModPortal: Upload Mods" and "ModPortal: Edit Mods".

Manual equivalents, with the key in `creds.txt`:

```bash
python build.py
python tools/portal.py upload  --key-file creds.txt
python tools/portal.py details --key-file creds.txt   # summary, description, FAQ, category, tags, license, links
python tools/portal.py images  --key-file creds.txt   # gallery, from dist/portal-images (see PORTAL.md)
```

Releases cannot be deleted through the API; use the portal website for that.

## 6. Portal page

Maintained from `portal/`: `summary.txt` (max 500 characters), `description.md`, `faq.md`, `meta.json`
(category, tags, license, homepage, source_url). `tools/portal.py details` pushes them; the workflow does it
on every release. Gallery images come from the client check, cropped by `tests/portal_images.ps1` into
`dist/portal-images/`, and are uploaded in file-name order (the first is the cover). Allowed values for
category, tags and license are listed in PORTAL.md.

The public read API (`/api/mods/research-debt/full`) lags behind edits for a while; check the page itself.

## 7. Tuning balance

- Debt per tech: `rd-step` (startup setting, default 0.1) × tier factor (`Tiers.Balance.factors`).
- Consolidation: `rd-consolidation-value` (0.25 per level); cost formula in data.lua (`500*1.5^(L-1)`).
- Archive: `Values.items` (points per item), `Values.Balance` (debt per point, half-life of diminishing
  returns, quality bonus, request bonus/target/limits/queue size).
- Trades: `Trades.Balance` (lab step and max, evolution step and cap, debt per trade).
- Bonus: `rd-debt-free-bonus` (map setting, default 0.2).
- Limits: `rd-max-multiplier`, `rd-min-multiplier` (map settings).

After changing a number, run the headless suite: most checks compute their expectations from the live
values, so they keep passing, but a few assert specific defaults (noted in the test names).

## 8. Known limitations

- The multiplier is global; PvP forces share it. Lab trades, requests and the bonus are per force.
- The technology screen and research queue cannot be extended by mods; the lab GUI panel is the closest.
- Not tested in real multiplayer yet.
- Mods that also write the technology price multiplier are unsupported (the watchdog re-applies ours).
