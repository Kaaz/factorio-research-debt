"""Factorio mod portal client for this repository.

    python tools/portal.py publish   # first publication (zip + description, category, license, source)
    python tools/portal.py upload    # add the dist zips (2.1 and 2.0 lines) as releases, skipping existing ones
    python tools/portal.py details   # push portal/summary.txt, description.md, faq.md, meta.json
    python tools/portal.py images    # upload dist/portal-images/*.png and set their order
    python tools/portal.py release   # upload + details (what the GitHub workflow runs)

The API key comes from the environment variable FACTORIO_API_KEY, or from a file given with
--key-file (a line "key=VALUE" or just the value). The key is never printed.

API reference: wiki.factorio.com Mod_upload_API, Mod_publish_API, Mod_details_API, Mod_images_API.
"""
import argparse
import json
import os
import sys
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent.parent
MOD_DIR = ROOT / "research-debt"
PORTAL_DIR = ROOT / "portal"
BASE = "https://mods.factorio.com/api/v2/mods"


def info():
    return json.loads((MOD_DIR / "info.json").read_text(encoding="utf-8"))


def zip_path(line=None):
    """dist zip for a Factorio line ("2.0", "2.1"); default: the line in info.json."""
    i = info()
    if line and line != i["factorio_version"]:
        version = f"{line}.{i['version'].split('.')[-1]}"
        return ROOT / "dist" / f"factorio-{line}" / f"{i['name']}_{version}.zip"
    return ROOT / "dist" / f"{i['name']}_{i['version']}.zip"


def portal_releases():
    r = requests.get(f"https://mods.factorio.com/api/mods/{info()['name']}/full", timeout=30)
    if r.status_code == 404:
        return None
    return [x["version"] for x in r.json().get("releases", [])]


def load_key(key_file):
    key = os.environ.get("FACTORIO_API_KEY", "").strip()
    if not key and key_file:
        text = Path(key_file).read_text(encoding="utf-8").strip()
        for line in text.splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key = line.split("=", 1)[-1].strip().strip('"').strip("'")
            break
    if not key:
        sys.exit("no API key: set FACTORIO_API_KEY or pass --key-file")
    return key


def check(resp, what):
    try:
        body = resp.json()
    except ValueError:
        body = {"error": "NoJSON", "message": resp.text[:300]}
    if not resp.ok or body.get("error"):
        sys.exit(f"{what} failed ({resp.status_code}): {body.get('error')}: {body.get('message')}")
    return body


def auth(key):
    return {"Authorization": f"Bearer {key}"}


def meta():
    return json.loads((PORTAL_DIR / "meta.json").read_text(encoding="utf-8"))


def read(name):
    return (PORTAL_DIR / name).read_text(encoding="utf-8").strip()


# --------------------------------------------------------------------------- commands

def cmd_publish(key, args):
    name = info()["name"]
    zp = zip_path()
    if not zp.exists():
        sys.exit(f"{zp} missing; run python build.py first")
    m = meta()
    r = requests.post(f"{BASE}/init_publish", data={"mod": name}, headers=auth(key), timeout=60)
    upload_url = check(r, "init_publish")["upload_url"]
    with zp.open("rb") as f:
        r = requests.post(upload_url, files={"file": f}, data={
            "description": read("description.md"),
            "category": m["category"],
            "license": m["license"],
            "source_url": m["source_url"],
        }, timeout=300)
    body = check(r, "publish upload")
    print("published:", body.get("url"))


def upload_zip(key, zp):
    name = info()["name"]
    if not zp.exists():
        sys.exit(f"{zp} missing; run python build.py --all first")
    version = zp.stem.split("_", 1)[1]
    existing = portal_releases() or []
    if version in existing:
        print("release", version, "already on the portal, skipping")
        return
    r = requests.post(f"{BASE}/releases/init_upload", data={"mod": name}, headers=auth(key), timeout=60)
    upload_url = check(r, "init_upload")["upload_url"]
    with zp.open("rb") as f:
        r = requests.post(upload_url, files={"file": f}, timeout=300)
    check(r, f"release upload {zp.name}")
    print("uploaded release", version, f"({zp.stat().st_size} bytes)")


def cmd_upload(key, args):
    lines = args.lines or [info()["factorio_version"], "2.0"]
    for line in dict.fromkeys(lines):
        upload_zip(key, zip_path(line))


def cmd_details(key, args):
    name = info()["name"]
    m = meta()
    summary = read("summary.txt")
    if len(summary) > 500:
        sys.exit(f"summary is {len(summary)} characters, max 500")
    data = {
        "mod": name,
        "title": info()["title"],
        "summary": summary,
        "description": read("description.md"),
        "faq": read("faq.md"),
        "category": m["category"],
        "license": m["license"],
        "homepage": m["homepage"],
        "source_url": m["source_url"],
        "tags": m["tags"],  # requests sends a list as repeated form fields
    }
    r = requests.post(f"{BASE}/edit_details", data=data, headers=auth(key), timeout=60)
    body = check(r, "edit_details")
    print("details updated:", body.get("url"))


def cmd_images(key, args):
    name = info()["name"]
    folder = ROOT / "dist" / "portal-images"
    files = sorted(folder.glob("*.png"))
    if not files:
        sys.exit(f"no images in {folder}; run tests/gui_check.py and tests/portal_images.ps1")
    import hashlib
    ids = []
    for p in files:
        # the portal identifies images by the SHA1 of the file, so an image that was uploaded
        # before (by hand or by an earlier run) can simply be referenced again
        sha1 = hashlib.sha1(p.read_bytes()).hexdigest()
        r = requests.post(f"{BASE}/images/add", data={"mod": name}, headers=auth(key), timeout=60)
        upload_url = check(r, f"images/add {p.name}")["upload_url"]
        with p.open("rb") as f:
            r = requests.post(upload_url, files={"image": f}, timeout=300)
        body = r.json() if r.content else {}
        if body.get("id"):
            ids.append(body["id"])
            print("uploaded", p.name, "->", body["id"][:12])
        elif "already exists" in str(body.get("message", "")).lower():
            ids.append(sha1)
            print("already on the portal", p.name, "->", sha1[:12])
        else:
            check(r, f"image upload {p.name}")
    r = requests.post(f"{BASE}/images/edit", data={"mod": name, "images": ",".join(ids)}, headers=auth(key), timeout=60)
    check(r, "images/edit")
    print("image order set:", len(ids), "images")


def cmd_release(key, args):
    cmd_upload(key, args)
    cmd_details(key, args)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["publish", "upload", "details", "images", "release"])
    ap.add_argument("--key-file", default=None, help="file with the API key (ignored when FACTORIO_API_KEY is set)")
    ap.add_argument("--lines", nargs="*", default=None, help='Factorio lines to upload (default: info.json line and 2.0)')
    args = ap.parse_args()
    key = load_key(args.key_file)
    {"publish": cmd_publish, "upload": cmd_upload, "details": cmd_details,
     "images": cmd_images, "release": cmd_release}[args.command](key, args)


if __name__ == "__main__":
    main()
