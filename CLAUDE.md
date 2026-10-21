# Research Debt – notes for AI sessions

- Read DEVELOPMENT.md (how to build, test, release) and NOTES.md (verified API facts, design decisions) first.
- Verify API behaviour against the installed docs in `Factorio/doc-html/*.json` or with an RCON experiment;
  do not guess. Record new findings in NOTES.md.
- Tests run against real Factorio: `python tests/run.py` (2.1, Steam) and the WSL command in DEVELOPMENT.md
  (2.0.77 headless). Both must be green before a release; the client check `tests/gui_check.py` opens a
  game window on the user's screen, say so before running it.
- Never touch `%APPDATA%\Factorio` except to copy the mod folder there when the user asks and Factorio is closed.
- `creds.txt` holds the portal API key: git-ignored, never print it, never commit it.
- All debt changes go through `Debt.add`; balance numbers go in the tables, not in logic; user-facing text
  goes through locale keys in English and Dutch.
- Docs and portal texts are English, in the author's own voice (plain, first person, no marketing tone).
- Publishing to the mod portal or GitHub is the user's call: ask before `tools/portal.py publish/upload/details`.
- Bash heredocs with apostrophes fail in this environment; write files with the Write tool or a Python script file.
