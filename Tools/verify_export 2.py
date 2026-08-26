#!/usr/bin/env python3
"""
verify_export.py — check a Figma export against the expected asset list.

    python3 Tools/verify_export.py Asset-Final/exported

Checks:
  * every expected asset name is present   (reads Asset-Final/MISSING-ASSETS.md)
  * flags files that aren't on the list    (usually a layer-name typo in Figma)
  * @2x / @3x companions are consistent
  * PNGs actually have transparency        (needs Pillow; skipped if absent)
  * flags suspiciously small renders

Exit code is 1 if anything is missing, so it can gate a build step.
"""
import argparse
import os
import re
import sys
from collections import defaultdict

try:
    from PIL import Image
    HAVE_PIL = True
except ImportError:
    HAVE_PIL = False

HERE = os.path.dirname(os.path.abspath(__file__))
DEFAULT_LIST = os.path.join(HERE, "..", "Asset-Final", "MISSING-ASSETS.md")

# Assets that legitimately have no transparency — full-bleed scene art.
OPAQUE_OK = {"bg-forest-flow", "bg-forest-station", "bg-kitchen-clearing",
             "bg-storage-rack", "bg-cabinet-interior"}

SCALE_RE = re.compile(r"^(?P<base>.+?)(?:@(?P<scale>[234])x)?\.(?P<ext>png|jpg|svg|pdf)$", re.I)


def expected_from_md(path):
    """Pull asset names out of the '| `name` |' first column of each table."""
    if not os.path.exists(path):
        return set()
    names, section = set(), None
    for line in open(path, encoding="utf8"):
        if line.startswith("## "):
            section = line.strip()
        if section and section.startswith("## Already covered"):
            continue
        m = re.match(r"\|\s*`([a-z0-9][a-z0-9-]*)`\s*\|", line)
        if m:
            names.add(m.group(1))
    return names


def scan(folder):
    """-> {base_name: {scale: path}}"""
    found = defaultdict(dict)
    for dirpath, _, filenames in os.walk(folder):
        for fn in filenames:
            m = SCALE_RE.match(fn)
            if not m:
                continue
            base = m.group("base")
            scale = int(m.group("scale") or 1)
            found[base][scale] = os.path.join(dirpath, fn)
    return found


def alpha_report(path):
    """-> (has_alpha_channel, fraction_transparent, (w,h)) or None"""
    if not HAVE_PIL:
        return None
    try:
        im = Image.open(path)
        size = im.size
        if im.mode not in ("RGBA", "LA", "P"):
            return (False, 0.0, size)
        im = im.convert("RGBA")
        a = im.getchannel("A")
        hist = a.histogram()
        total = sum(hist)
        clear = sum(hist[:250])
        return (True, clear / total if total else 0.0, size)
    except Exception:
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("folder", help="folder of exported assets")
    ap.add_argument("--list", default=DEFAULT_LIST,
                    help="markdown file holding the expected names")
    ap.add_argument("--min-size", type=int, default=40,
                    help="warn if a render is smaller than this on either side")
    args = ap.parse_args()

    if not os.path.isdir(args.folder):
        raise SystemExit(f"not a folder: {args.folder}")

    expected = expected_from_md(args.list)
    found = scan(args.folder)

    if not expected:
        print(f"! could not read expected names from {args.list}")
        print(f"  scanned anyway: {len(found)} assets in {args.folder}")

    missing = sorted(expected - set(found))
    extra = sorted(set(found) - expected) if expected else []
    present = sorted(expected & set(found)) if expected else sorted(found)

    print(f"expected {len(expected)}  |  found {len(found)}  |  "
          f"matched {len(present)}\n")

    if missing:
        print(f"MISSING — {len(missing)}")
        for n in missing:
            print(f"   {n}")
        print()

    if extra:
        print(f"NOT ON THE LIST — {len(extra)}  (layer-name typo in Figma?)")
        for n in extra:
            print(f"   {n}")
        print()

    # scale consistency
    scale_sets = defaultdict(list)
    for base, by_scale in found.items():
        scale_sets[tuple(sorted(by_scale))].append(base)
    if len(scale_sets) > 1:
        print("INCONSISTENT SCALES")
        for combo, names in sorted(scale_sets.items(), key=lambda kv: -len(kv[1])):
            label = ", ".join(f"@{s}x" if s > 1 else "@1x" for s in combo)
            print(f"   {label}: {len(names)}" +
                  ("" if len(names) > 6 else "  " + " ".join(names)))
        print()

    # pixel checks
    warn = []
    if HAVE_PIL:
        for base in sorted(found):
            path = found[base].get(1) or list(found[base].values())[0]
            if not path.lower().endswith((".png", ".jpg")):
                continue
            rep = alpha_report(path)
            if not rep:
                continue
            has_alpha, clear_frac, (w, h) = rep
            if base not in OPAQUE_OK and (not has_alpha or clear_frac < 0.005):
                warn.append(f"   {base}: no transparent pixels "
                            f"— did you export the frame instead of the element?")
            if min(w, h) < args.min_size:
                warn.append(f"   {base}: only {w}x{h} — check the scale")
    else:
        print("(install Pillow for transparency + size checks: "
              "pip3 install pillow)\n")

    if warn:
        print(f"PIXEL WARNINGS — {len(warn)}")
        print("\n".join(warn))
        print()

    if not missing and not extra and not warn:
        print("All good.")

    return 1 if missing else 0


if __name__ == "__main__":
    sys.exit(main())
