"""Builds the mod zips in the layout Factorio and the mod portal expect.

    python build.py                 # the line in info.json (2.1): dist/research-debt_2.1.<patch>.zip
    python build.py --factorio 2.0  # the 2.0 line:                dist/factorio-2.0/research-debt_2.0.<patch>.zip
    python build.py --all           # both

Version scheme: the mod version is <factorio line>.<patch>, e.g. 2.1.0 for Factorio 2.1 and 2.0.0 for
Factorio 2.0, built from one source. For the other line the zip gets a rewritten info.json
(`version`, `factorio_version`, `base >=`) and the first "Version:" header of changelog.txt.
"""
import argparse
import json
import pathlib
import re
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
MOD = ROOT / "research-debt"


def target_version(info, factorio):
    patch = info["version"].split(".")[-1]
    return f"{factorio}.{patch}"


def build(factorio=None):
    info = json.loads((MOD / "info.json").read_text(encoding="utf-8"))
    out_dir = ROOT / "dist"
    changelog = (MOD / "changelog.txt").read_text(encoding="utf-8")
    if factorio and factorio != info["factorio_version"]:
        info["version"] = target_version(info, factorio)
        info["factorio_version"] = factorio
        info["dependencies"] = [re.sub(r"^base\s*>=\s*[\d.]+", f"base >= {factorio}", d) for d in info["dependencies"]]
        changelog = re.sub(r"^Version: .*$", f"Version: {info['version']}", changelog, count=1, flags=re.M)
        out_dir = out_dir / f"factorio-{factorio}"
    out_dir.mkdir(parents=True, exist_ok=True)
    folder = f"{info['name']}_{info['version']}"
    out = out_dir / f"{folder}.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
        for p in sorted(MOD.rglob("*")):
            if not p.is_file():
                continue
            rel = p.relative_to(MOD).as_posix()
            if rel == "info.json":
                z.writestr(f"{folder}/info.json", json.dumps(info, indent=2, ensure_ascii=False) + "\n")
            elif rel == "changelog.txt":
                z.writestr(f"{folder}/changelog.txt", changelog)
            else:
                z.write(p, f"{folder}/{rel}")
    print(out, out.stat().st_size, "bytes", f"(factorio {info['factorio_version']}, version {info['version']})")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--factorio", help='target Factorio line, e.g. "2.0" (default: as in info.json)')
    ap.add_argument("--all", action="store_true", help="build the info.json line and 2.0")
    a = ap.parse_args()
    if a.all:
        build()
        build("2.0")
    else:
        build(a.factorio)
