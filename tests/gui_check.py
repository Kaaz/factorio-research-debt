"""Opens the real Factorio client on an isolated test save with a tiny helper mod that
opens the Research Debt window and writes screenshots to script-output. The client
window is closed automatically when the screenshots exist (or after a timeout).

    python tests/gui_check.py

Output: <env>/data/script-output/rd-gui-*.png and a log excerpt.
"""
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run import Env, DEFAULT_FACTORIO, MOD_SRC  # noqa: E402

SELFTEST = Path(__file__).resolve().parent / "selftest-mod"
ENV = Path(os.environ.get("LOCALAPPDATA", str(Path.home()))) / "Temp" / "rd-test-gui"


def main():
    env = Env(DEFAULT_FACTORIO, ENV, True)
    env.prepare()
    # windowed client so the test does not take over the screen
    with env.config.open("a", encoding="utf-8") as f:
        f.write("\n[graphics]\nfull-screen=false\n")
    info = json.loads((SELFTEST / "info.json").read_text(encoding="utf-8"))
    dst = env.mods / f"rd-gui-selftest_{info['version']}"
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(SELFTEST, dst)
    ml = json.loads((env.mods / "mod-list.json").read_text(encoding="utf-8"))
    ml["mods"].append({"name": "rd-gui-selftest", "enabled": True})
    (env.mods / "mod-list.json").write_text(json.dumps(ml, indent=1), encoding="utf-8")

    save = env.create_save("gui.zip")
    out = env.data / "script-output"
    out.mkdir(parents=True, exist_ok=True)
    for f in list(out.glob("rd-gui-*.png")) + list(out.glob("rd-gui-progress.txt")):
        f.unlink()
    progress = out / "rd-gui-progress.txt"
    if env.log.exists():
        env.log.unlink()
    cmd = [str(env.factorio), "-c", str(env.config), "--mod-directory", str(env.mods),
           "--load-game", str(save), "--disable-audio", "--disable-migration-window"]
    print("starting client:", " ".join(cmd))
    proc = subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    # The Steam build may relaunch itself through Steam, so `proc` can exit at once while the
    # real client keeps running. Poll the progress file and clean up by command line.
    deadline = time.time() + 150
    done = False
    try:
        while time.time() < deadline:
            time.sleep(2)
            if progress.exists() and "DONE" in progress.read_text(encoding="utf-8", errors="replace"):
                done = True
                time.sleep(3)  # let the last screenshot flush
                break
            if proc.poll() is not None and proc.returncode not in (0, None) :
                break
    finally:
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=30)
        subprocess.run(["powershell", "-NoProfile", "-Command",
                        "Get-CimInstance Win32_Process -Filter \"Name='factorio.exe'\" | "
                        "Where-Object { $_.CommandLine -like '*rd-test-gui*' } | "
                        "ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"],
                       capture_output=True)
    shots = sorted(out.glob("rd-gui-*.png"))
    print("done:", done, "exit:", proc.returncode, "screenshots:", [str(s) for s in shots])
    if progress.exists():
        print("progress:\n  " + progress.read_text(encoding="utf-8", errors="replace").strip().replace("\n", "\n  "))
    if env.log.exists():
        for line in env.log.read_text(encoding="utf-8", errors="replace").splitlines():
            if "rd-gui-selftest" in line or "research-debt" in line.lower() and "rror" in line:
                print("  ", line.strip()[:220])
    return 0 if done and len(shots) >= 3 else 1


if __name__ == "__main__":
    sys.exit(main())
