"""Builds the mod zip in the layout Factorio and the mod portal expect.

    python build.py                 # dist/research-debt_<version>.zip for the factorio_version in info.json
    python build.py --factorio 2.0  # same source, info.json rewritten for Factorio 2.0, in dist/factorio-2.0/

The source stays on one Factorio line (info.json); the other line is produced at build time by
rewriting `factorio_version` and the `base` dependency inside the zip only.
"""
import argparse
import json
import pathlib
import re
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
MOD = ROOT / "research-debt"


def build(factorio=None, version=None):
    info = json.loads((MOD / "info.json").read_text(encoding="utf-8"))
    if version:
        info["version"] = version
    out_dir = ROOT / "dist"
    if factorio and factorio != info["factorio_version"]:
        info["factorio_version"] = factorio
        info["dependencies"] = [re.sub(r"^base\s*>=\s*[\d.]+", f"base >= {factorio}", d) for d in info["dependencies"]]
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
            else:
                z.write(p, f"{folder}/{rel}")
    print(out, out.stat().st_size, "bytes", f"(factorio {info['factorio_version']}, version {info['version']})")
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--factorio", help='target Factorio line, e.g. "2.0" (default: as in info.json)')
    ap.add_argument("--version", help="override the mod version inside the zip")
    a = ap.parse_args()
    build(a.factorio, a.version)
