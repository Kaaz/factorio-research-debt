"""Builds dist/research-debt_<version>.zip in the layout Factorio and the mod portal expect."""
import json, pathlib, zipfile

root = pathlib.Path(__file__).resolve().parent
mod = root / "research-debt"
ver = json.loads((mod / "info.json").read_text(encoding="utf-8"))["version"]
out = root / "dist" / f"research-debt_{ver}.zip"
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as z:
    for p in sorted(mod.rglob("*")):
        if p.is_file():
            z.write(p, f"research-debt_{ver}/{p.relative_to(mod).as_posix()}")
print(out, out.stat().st_size, "bytes")
