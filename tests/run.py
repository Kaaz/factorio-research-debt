"""End-to-end tests for the Research Debt mod against a real headless Factorio server.

Usage:
    python tests/run.py                 # full run (Space Age if installed)
    python tests/run.py --no-space-age  # vanilla only
    python tests/run.py --keep          # keep the test environment after the run
    python tests/run.py --only phase1   # run a subset (phase1, phase2, phase3, persist, existing, nosa)

Nothing in the user's normal Factorio folders is touched: a separate write-data
folder (config, mods, saves, log) is used via --config.
"""
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
import zipfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from rcon import wait_for_rcon  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MOD_SRC = ROOT / "research-debt"
DEFAULT_FACTORIO = Path(r"C:\Program Files (x86)\Steam\steamapps\common\Factorio\bin\x64\factorio.exe")
DEFAULT_ENV = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "Temp" / "rd-test"
RCON_PORT = 27115
RCON_PASSWORD = "rd-test-" + str(int(time.time()))[-6:]
GAME_PORT = 34215


# --------------------------------------------------------------------------- env

class Env:
    def __init__(self, factorio: Path, root: Path, space_age: bool, line: str = None):
        self.factorio = factorio
        self.root = root
        self.space_age = space_age
        self.line = line  # Factorio line to test against ("2.0"); rewrites info.json like build.py
        self.data = root / "data"
        self.mods = self.data / "mods"
        self.saves = self.data / "saves"
        self.config = root / "config" / "config.ini"
        self.server_settings = root / "config" / "server-settings.json"
        self.log = self.data / "factorio-current.log"
        self.proc = None
        self.rcon = None

    def prepare(self, mod_enabled=True):
        for d in (self.mods, self.saves, self.config.parent):
            d.mkdir(parents=True, exist_ok=True)
        self.config.write_text(
            "[path]\nread-data=__PATH__system-read-data__\n"
            f"write-data={self.data.as_posix()}\n", encoding="utf-8")
        self.server_settings.write_text(json.dumps({
            "name": "research-debt test", "description": "", "tags": [], "max_players": 0,
            "visibility": {"public": False, "lan": False},
            "username": "", "password": "", "token": "", "game_password": "",
            "require_user_verification": False, "max_upload_in_kilobytes_per_second": 0,
            "max_upload_slots": 5, "minimum_latency_in_ticks": 0, "max_heartbeats_per_second": 60,
            "ignore_player_limit_for_returning_players": False, "allow_commands": "admins-only",
            "autosave_interval": 0, "autosave_slots": 5, "afk_autokick_interval": 0,
            "auto_pause": False, "auto_pause_when_players_connect": False,
            "only_admins_can_pause_the_game": True, "autosave_only_on_server": True,
            "non_blocking_saving": False,
        }), encoding="utf-8")
        self.install_mod()
        self.write_mod_list(mod_enabled)

    def install_mod(self):
        info = json.loads((MOD_SRC / "info.json").read_text(encoding="utf-8"))
        for old in self.mods.glob("research-debt_*"):
            shutil.rmtree(old)
        dst = self.mods / f"research-debt_{info['version']}"
        shutil.copytree(MOD_SRC, dst)
        if self.line and self.line != info["factorio_version"]:
            import re
            info["factorio_version"] = self.line
            info["dependencies"] = [re.sub(r"^base\s*>=\s*[\d.]+", f"base >= {self.line}", d) for d in info["dependencies"]]
            (dst / "info.json").write_text(json.dumps(info, indent=2) + "
", encoding="utf-8")

    def write_mod_list(self, mod_enabled=True):
        mods = [{"name": "base", "enabled": True}]
        for name in ("space-age", "quality", "elevated-rails", "recycler"):
            mods.append({"name": name, "enabled": self.space_age})
        mods.append({"name": "research-debt", "enabled": mod_enabled})
        (self.mods / "mod-list.json").write_text(json.dumps({"mods": mods}, indent=1), encoding="utf-8")

    def write_mod_settings(self, startup: dict):
        """Startup settings are stored in mod-settings.dat (binary). We instead pass them
        through a small data-stage override? Not possible - so we patch via the JSON
        side-file Factorio accepts: none exists. Therefore startup settings are tested
        with their defaults; see NOTES.md."""
        raise NotImplementedError

    def _run(self, args, timeout=300):
        cmd = [str(self.factorio), "-c", str(self.config), "--mod-directory", str(self.mods)] + args
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, encoding="utf-8", errors="replace")

    def create_save(self, name="test.zip"):
        save = self.saves / name
        if save.exists():
            save.unlink()
        r = self._run(["--create", str(save)])
        if r.returncode != 0 or not save.exists():
            raise RuntimeError(f"--create failed:\n{r.stdout[-3000:]}\n{r.stderr[-2000:]}")
        return save

    def start_server(self, save: Path):
        assert self.proc is None
        if self.log.exists():
            try:
                self.log.unlink()
            except PermissionError:
                raise RuntimeError("factorio-current.log is locked: a previous test server is still running")
        cmd = [str(self.factorio), "-c", str(self.config), "--mod-directory", str(self.mods),
               "--start-server", str(save), "--server-settings", str(self.server_settings),
               "--bind", f"127.0.0.1:{GAME_PORT}",
               "--rcon-bind", f"127.0.0.1:{RCON_PORT}", "--rcon-password", RCON_PASSWORD]
        self.proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.rcon = wait_for_rcon("127.0.0.1", RCON_PORT, RCON_PASSWORD, timeout=180,
                                  is_alive=lambda: self.proc.poll() is None)
        # RCON can come up before the map has finished loading: wait until Lua answers.
        deadline = time.time() + 60
        while time.time() < deadline:
            out = self.rcon.command("/silent-command rcon.print('ready')")
            if out.strip() == "ready":
                return self.rcon
            time.sleep(0.5)
        raise RuntimeError("server never became ready for commands")

    def stop_server(self, save_as=None):
        if self.rcon:
            try:
                if save_as:
                    self.rcon.command(f"/server-save {save_as}")
                    time.sleep(2.0)
                self.rcon.command("/quit")
            except Exception:
                pass
            self.rcon.close()
            self.rcon = None
        if self.proc:
            try:
                self.proc.wait(timeout=60)
            except subprocess.TimeoutExpired:
                self.proc.kill()
            self.proc = None

    # -- Lua helpers ---------------------------------------------------------
    def lua(self, code: str) -> str:
        return self.rcon.command("/silent-command " + code)

    def lua_json(self, expr: str):
        out = self.lua(f"rcon.print(helpers.table_to_json({{v={expr}}}))")
        try:
            return json.loads(out).get("v")
        except Exception as e:  # pragma: no cover
            raise RuntimeError(f"bad JSON from Lua for {expr!r}: {out!r}") from e

    def status(self):
        return self.lua_json('remote.call("research-debt","status")')

    def log_errors(self):
        if not self.log.exists():
            return []
        bad = []
        for line in self.log.read_text(encoding="utf-8", errors="replace").splitlines():
            if re.search(r"\bError\b", line) and "research-debt" in line.lower() or " Error " in line and "Lua" in line:
                bad.append(line.strip())
        return bad


# --------------------------------------------------------------------------- test harness

class T:
    def __init__(self):
        self.results = []

    def check(self, name, cond, detail=""):
        self.results.append((name, bool(cond), detail))
        print(("  PASS  " if cond else "  FAIL  ") + name + (f"   [{detail}]" if detail else ""), flush=True)
        return cond

    def approx(self, name, got, want, tol=1e-6):
        return self.check(name, abs(got - want) <= tol, f"got {got:.6f}, want {want:.6f}")

    def summary(self):
        failed = [r for r in self.results if not r[1]]
        print(f"\n{len(self.results) - len(failed)}/{len(self.results)} checks passed")
        for name, _, detail in failed:
            print(f"  FAILED: {name}  {detail}")
        return not failed


def research(env, *names):
    for n in names:
        env.lua(f'local t=game.forces.player.technologies["{n}"]; if t then t.researched=true end')


# 10 cheap vanilla non-infinite techs that exist with and without Space Age
BASIC_TECHS = ["automation", "logistics", "electronics", "steel-processing", "military",
               "logistic-science-pack", "fast-inserter", "automobilism", "optics", "turrets"]


# --------------------------------------------------------------------------- phases

def phase1(env: Env, t: T):
    print("\n== Phase 1: debt rises with research ==")
    s = env.status()
    t.approx("fresh save: debt is 0", s["debt"], 0)
    t.approx("fresh save: multiplier == base", s["actual_multiplier"], s["base_multiplier"])
    step = s["step"]

    # pick an infinite tech that exists in this mod set (name differs with Space Age)
    inf = env.lua_json('(function() for _,n in ipairs({"mining-productivity-3","mining-productivity-4"}) do '
                       'local p=prototypes.technology[n] if p and p.max_level==4294967295 then return n end end end)()')
    t.check("found an infinite technology", inf is not None, str(inf))
    info = env.lua_json(f'remote.call("research-debt","counts","{inf}")')
    t.check(f"{inf} is infinite and does not count", info["infinite"] and not info["counts"], f"max_level={info['max_level']}")
    info = env.lua_json('remote.call("research-debt","counts","steel-axe")')
    t.check("trigger tech steel-axe does not count (default setting)", info["trigger"] and not info["counts"])
    info = env.lua_json('remote.call("research-debt","counts","logistics")')
    t.check("logistics counts", info["counts"] and not info["infinite"])
    info = env.lua_json('remote.call("research-debt","counts","automation")')
    t.check("automation (vanilla ignore_tech_cost_multiplier) still counts", info["counts"])

    normal = "advanced-electronics" if env.lua_json('prototypes.technology["advanced-electronics"] ~= nil') else "engine"
    inf_before = env.lua_json(f'game.forces.player.technologies["{inf}"].research_unit_count')
    norm_before = env.lua_json(f'game.forces.player.technologies["{normal}"].research_unit_count')

    basic = [n for n in BASIC_TECHS if env.lua_json(f'prototypes.technology["{n}"] ~= nil')]
    counting = [n for n in basic if env.lua_json(f'remote.call("research-debt","counts","{n}").counts')]
    expected = len(counting)
    expected_debt = sum(env.lua_json(f'remote.call("research-debt","step_for","{n}").step') for n in counting)
    research(env, *basic)
    s = env.status()
    print(f"  INFO  {expected} of {len(BASIC_TECHS)} techs count in this mod set, tier-weighted debt {expected_debt:.3f}")
    t.approx(f"{expected} techs: debt == sum of tier steps", s["debt"], expected_debt)
    t.approx("multiplier == base*(1+debt)", s["actual_multiplier"], s["base_multiplier"] * (1 + expected_debt), 1e-6)
    t.check("stats.techs_counted matches", s["stats"]["techs_counted"] == expected, str(s["stats"]["techs_counted"]))

    inf_after = env.lua_json(f'game.forces.player.technologies["{inf}"].research_unit_count')
    norm_after = env.lua_json(f'game.forces.player.technologies["{normal}"].research_unit_count')
    t.check("infinite tech cost unchanged", inf_before == inf_after, f"{inf_before} -> {inf_after}")
    t.check("normal tech cost scaled by multiplier", norm_after == round(norm_before * s["actual_multiplier"]),
            f"{norm_before} -> {norm_after} (mult {s['actual_multiplier']:.3f})")

    # researching a level of an infinite tech must not add debt
    before = env.status()["debt"]
    lvl_before = env.lua_json(f'game.forces.player.technologies["{inf}"].level')
    env.lua(f'game.forces.player.technologies["{inf}"].researched=true')
    s = env.status()
    t.approx("researching an infinite tech level adds no debt", s["debt"], before)
    t.check("infinite tech level increased", env.lua_json(f'game.forces.player.technologies["{inf}"].level') == lvl_before + 1)
    inf_after2 = env.lua_json(f'game.forces.player.technologies["{inf}"].research_unit_count')
    print(f"  INFO  {inf} level {lvl_before} -> {lvl_before + 1}, next level costs {inf_after2} units")

    # reverse
    step_logistics = env.lua_json('remote.call("research-debt","step_for","logistics").step')
    env.lua('game.forces.player.technologies["logistics"].researched=false')
    s = env.status()
    t.approx("reversing a tech removes its own step", s["debt"], before - step_logistics)
    t.check("reversed counter", s["stats"]["reversed"] == 1)
    research(env, "logistics")

    # max clamp
    # runtime-global settings can only be written by the owning mod -> remote set_setting
    env.lua('remote.call("research-debt","set_setting","rd-max-multiplier",1.2)')
    s = env.status()
    t.approx("max-multiplier setting clamps", s["actual_multiplier"], 1.2)
    t.check("clamped status reports raw > actual", s["raw_multiplier"] > s["actual_multiplier"])
    env.lua('remote.call("research-debt","set_setting","rd-max-multiplier",50)')
    s = env.status()
    t.approx("clamp released", s["actual_multiplier"], s["base_multiplier"] * (1 + s["debt"]))

    # watchdog: another mod/script writing the multiplier is corrected within 60 ticks
    env.lua("game.difficulty_settings.technology_price_multiplier = 7")
    time.sleep(1.5)
    s = env.status()
    t.approx("watchdog restores the multiplier after external write", s["actual_multiplier"], s["multiplier"])

    # min clamp: pay off more than owed
    env.lua('remote.call("research-debt","add_debt",-100,"test")')
    s = env.status()
    t.approx("debt never negative", s["debt"], 0)
    t.approx("multiplier never below base*min", s["actual_multiplier"], s["base_multiplier"])
    env.lua('remote.call("research-debt","recalculate")')
    s = env.status()
    t.approx("recalculate restores debt from researched techs", s["debt"], expected_debt)

    # in-progress research survives a multiplier change (observe + document)
    env.lua('game.forces.player.research_queue={"engine"}')
    env.lua('game.forces.player.research_progress=0.5')
    prog_before = env.lua_json("game.forces.player.research_progress")
    units_before = env.lua_json('game.forces.player.technologies["engine"].research_unit_count')
    env.lua('remote.call("research-debt","add_debt",1.0,"test")')
    prog_after = env.lua_json("game.forces.player.research_progress")
    units_after = env.lua_json('game.forces.player.technologies["engine"].research_unit_count')
    print(f"  INFO  in-progress research: progress {prog_before:.3f} -> {prog_after:.3f}, units {units_before} -> {units_after}")
    t.check("in-progress research still active after multiplier change",
            env.lua_json('game.forces.player.current_research and game.forces.player.current_research.name') == "engine")
    env.lua('remote.call("research-debt","add_debt",-1.0,"test")')
    env.lua("game.forces.player.cancel_current_research()")

    out = env.rcon.command("/rd-status")
    t.check("/rd-status prints", "debt=" in out, out[:120])


def persist(env: Env, t: T, save: Path):
    print("\n== Persistence: save, restart, compare ==")
    before = env.status()
    env.stop_server(save_as="persist")
    env.start_server(env.saves / "persist.zip")
    after = env.status()
    t.approx("debt persists across restart", after["debt"], before["debt"])
    t.approx("multiplier persists across restart", after["actual_multiplier"], before["actual_multiplier"])
    t.approx("base persists across restart", after["base_multiplier"], before["base_multiplier"])


def existing_save(env: Env, t: T):
    print("\n== Mod added to an existing save ==")
    env.stop_server()
    env.write_mod_list(mod_enabled=False)
    save = env.create_save("existing.zip")
    env.start_server(save)
    techs = BASIC_TECHS + ["engine", "advanced-material-processing", "electric-energy-distribution-1", "gun-turret",
                           "stone-wall", "heavy-armor", "fluid-handling", "oil-processing", "circuit-network",
                           "landfill"]
    for n in techs:
        env.lua(f'local t=game.forces.player.technologies["{n}"]; if t then t.researched=true end')
    n_researched = env.lua_json('(function() local n=0 for _,t in pairs(game.forces.player.technologies) do if t.researched then n=n+1 end end return n end)()')
    print(f"  INFO  {n_researched} technologies researched without the mod")
    env.stop_server(save_as="existing")
    env.write_mod_list(mod_enabled=True)
    env.start_server(env.saves / "existing.zip")
    s = env.status()
    # Count what the mod itself considers countable among the researched ones
    expected = env.lua_json(
        '(function() local n=0 for _,t in pairs(game.forces.player.technologies) do '
        'if t.researched and remote.call("research-debt","counts",t.name).counts then n=n+1 end end return n end)()')
    t.check("existing save: counted techs > 0", expected > 0, f"counted={expected} of {n_researched} researched")
    expected_debt = env.lua_json(
        '(function() local d=0 for _,t in pairs(game.forces.player.technologies) do '
        'if t.researched and remote.call("research-debt","counts",t.name).counts then d=d+remote.call("research-debt","step_for",t.name).step end end return d end)()')
    t.approx("existing save: debt == sum of tier steps", s["debt"], expected_debt)
    t.approx("existing save: multiplier applied", s["actual_multiplier"], s["base_multiplier"] * (1 + s["debt"]))


# --------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--factorio", type=Path, default=DEFAULT_FACTORIO)
    ap.add_argument("--env", type=Path, default=DEFAULT_ENV)
    ap.add_argument("--no-space-age", action="store_true")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--only", nargs="*", default=None)
    ap.add_argument("--line", default=None, help='Factorio line of the installation under test, e.g. "2.0"')
    args = ap.parse_args()

    only = set(args.only) if args.only else None
    want = lambda k: only is None or k in only  # noqa: E731

    space_age = (not args.no_space_age) and (args.factorio.parent.parent.parent / "data" / "space-age").exists()
    print(f"Factorio: {args.factorio}\nEnv: {args.env}\nSpace Age: {space_age}")
    env = Env(args.factorio, args.env, space_age, args.line)
    t = T()
    try:
        env.prepare()
        save = env.create_save("test.zip")
        env.start_server(save)
        ver = env.lua_json("script.active_mods.base")
        mods = env.lua_json("script.active_mods")
        print(f"Game {ver}, mods: {', '.join(f'{k} {v}' for k, v in mods.items())}")
        t.check("mod loaded", "research-debt" in mods)

        if want("phase1"):
            phase1(env, t)
        if want("phase2"):
            from phases import phase2
            phase2(env, t)
        if want("phase3"):
            from phases import phase3
            phase3(env, t)
        if want("gui"):
            from phases import gui
            gui(env, t)
        if want("trades"):
            from phases import trades
            trades(env, t)
        if want("tiers"):
            from phases import tiers
            tiers(env, t)
        if want("bonus"):
            from phases import bonus
            bonus(env, t)
        if want("requests"):
            from phases import requests
            requests(env, t)
        if want("persist"):
            persist(env, t, save)
        if want("existing"):
            existing_save(env, t)
        env.stop_server()
        errs = env.log_errors()
        t.check("no Lua errors in log", not errs, "; ".join(errs)[:300])

        if want("nosa") and space_age:
            print("\n== Load without Space Age ==")
            env2 = Env(args.factorio, args.env, False, args.line)
            env2.prepare()
            s2 = env2.create_save("vanilla.zip")
            env2.start_server(s2)
            mods = env2.lua_json("script.active_mods")
            t.check("vanilla: loads without space-age", "research-debt" in mods and "space-age" not in mods)
            st = env2.status()
            t.approx("vanilla: multiplier == base", st["actual_multiplier"], st["base_multiplier"])
            research(env2, *BASIC_TECHS[:4])
            exp = sum(env2.lua_json(f'remote.call("research-debt","step_for","{n}").step') for n in BASIC_TECHS[:4]
                      if env2.lua_json(f'remote.call("research-debt","counts","{n}").counts'))
            st = env2.status()
            t.approx("vanilla: tier-weighted debt of 4 techs", st["debt"], exp)
            if want("phase2"):
                from phases import phase2
                phase2(env2, t, vanilla=True)
            if want("phase3"):
                from phases import phase3
                phase3(env2, t, vanilla=True)
            env2.stop_server()
            errs = env2.log_errors()
            t.check("vanilla: no Lua errors in log", not errs, "; ".join(errs)[:300])
    finally:
        env.stop_server()
        if not args.keep and args.env.exists() and t.summary():
            pass  # keep the env anyway: it is small and useful for debugging
    ok = all(r[1] for r in t.results)
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
