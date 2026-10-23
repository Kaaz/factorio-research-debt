# Mod portal

The portal page is maintained from this repository, not by hand.

Version scheme: plain counting from 2.1.1 on (bug fixes 2.1.x, new mechanics 2.2.0, a big overhaul 3.0.0).
The jump from 0.1.0 to 2.x came from a short-lived "mod version = Factorio line" scheme while 2.0 and 2.1 were
both served; Factorio only ever updates to a higher number, so there is no way back. Factorio 2.0 was served by
2.0.0 (same features) and is no longer updated; `build.py --factorio 2.0` still works.

```
portal/summary.txt      short text shown in listings (max 500 characters)
portal/description.md   the mod page (Markdown)
portal/faq.md           the FAQ tab (Markdown)
portal/meta.json        category, tags, license, homepage, source_url
research-debt/thumbnail.png   144×144, ships inside the zip, picked up automatically
dist/portal-images/*.png      gallery images, made by tests/gui_check.py + tests/portal_images.ps1
```

Allowed values (from the Mod details API): category `tweaks`, `content`, `overhaul`, `utilities`,
`scenarios`, `mod-packs`, `localizations`, `internal`; tags `transportation`, `logistics`, `trains`,
`combat`, `armor`, `enemies`, `environment`, `mining`, `fluids`, `logistic-network`, `circuit-network`,
`manufacturing`, `power`, `storage`, `blueprints`, `cheats`; license `default_mit`, `default_gnugplv3`,
`default_gnulgplv3`, `default_mozilla2`, `default_apache2`, `default_unlicense`, `custom_<id>`.

## Tool

`tools/portal.py` talks to the portal API. The key comes from `FACTORIO_API_KEY` or `--key-file creds.txt`
(`creds.txt` is git-ignored). Create the key at https://factorio.com/profile with the usages
"ModPortal: Upload Mods", "ModPortal: Edit Mods" and, for the first publication, "ModPortal: Publish Mods".

```bash
python build.py                                     # dist/research-debt_2.1.x.zip
python tools/portal.py publish --key-file creds.txt # first time only: creates the mod on the portal
python tools/portal.py details --key-file creds.txt # push summary, description, FAQ, category, tags, license, links
python tools/portal.py images  --key-file creds.txt # upload the gallery images in order (replaces the gallery)
python tools/portal.py upload  --key-file creds.txt # add the zip as a release (a version already on the portal is skipped)
```

## Releasing a new version

1. Bump the patch number of `version` in `research-debt/info.json` (e.g. 2.1.1) and add an entry to
   `research-debt/changelog.txt`.
2. Commit, then tag and push: `git tag v2.1.1 && git push origin master v2.1.1`.
3. The GitHub workflow (`.github/workflows/release.yml`) builds the zip, creates a GitHub release with
   the changelog entry as notes, uploads the zip to the portal and pushes the texts from `portal/`.
   It needs the repository secret `FACTORIO_API_KEY` (Settings → Secrets and variables → Actions).

Images are not part of the workflow; run `python tools/portal.py images` when the screenshots change.
