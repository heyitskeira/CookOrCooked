#!/usr/bin/env python3
"""
figma.py — read layout numbers and pull PNGs straight out of a Figma file.

Works on a free Figma account: the REST API needs only a personal access token,
not Dev Mode or a paid seat.

    Tools/figma.py frames  <file-url>
    Tools/figma.py layout  <file-url> <frame-name-or-id>
    Tools/figma.py export  <file-url> <node-id> <asset-name>

The token is read from ~/.config/figma/token, or $FIGMA_TOKEN. It is never
printed, never passed on a command line, and never written into the repo.

Why positions from here beat reading them off the Figma panel: the API reports
`absoluteBoundingBox`, which is the box a layer actually occupies on screen with
its rotation already applied. The panel reports pre-rotation width and height,
which is why a 90°-rotated signpost reads "W 201, H 160" but draws 160 wide.
Nothing here needs that conversion.
"""

import hashlib
import json
import os
import pathlib
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.figma.com/v1"

# Figma rate-limits reads hard enough that walking a few screens in a row will
# trip it. Responses are cached on disk so re-reading a frame — which happens
# constantly while nudging a layout — costs nothing.
CACHE = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / "figma-cache"
CACHE_SECONDS = 30 * 60
DROP = pathlib.Path(__file__).resolve().parent.parent / "Assets-agung" / "drop"


def token() -> str:
    env = os.environ.get("FIGMA_TOKEN")
    if env:
        return env.strip()
    path = pathlib.Path.home() / ".config" / "figma" / "token"
    if path.exists():
        return path.read_text().strip()
    sys.exit(
        "No Figma token found.\n"
        "Create one at Figma → your avatar → Settings → Security →\n"
        "Personal access tokens, then save it with:\n\n"
        "  mkdir -p ~/.config/figma && chmod 700 ~/.config/figma \\\n"
        "    && read -rs \"?Figma token: \" t \\\n"
        "    && printf '%s' \"$t\" > ~/.config/figma/token \\\n"
        "    && chmod 600 ~/.config/figma/token && unset t && echo saved\n"
    )


def get(path: str, use_cache: bool = True) -> dict:
    CACHE.mkdir(parents=True, exist_ok=True)
    # Keyed on the path only — the token never reaches the cache key or the
    # filename, so nothing secret lands on disk here.
    slot = CACHE / (hashlib.sha256(path.encode()).hexdigest()[:32] + ".json")
    if use_cache and slot.exists() and time.time() - slot.stat().st_mtime < CACHE_SECONDS:
        return json.loads(slot.read_text())

    request = urllib.request.Request(f"{API}{path}", headers={"X-Figma-Token": token()})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
            slot.write_text(json.dumps(payload))
            return payload
        except urllib.error.HTTPError as error:
            if error.code == 429 and attempt < 3:
                wait = 20 * (attempt + 1)
                print(f"  rate limited, waiting {wait}s…", file=sys.stderr)
                time.sleep(wait)
                continue
            # Deliberately not echoing the request headers — the token is there.
            body = error.read().decode("utf-8", "replace")[:400]
            sys.exit(f"Figma API {error.code} on {path}\n{body}")
    sys.exit(f"Figma API kept rate limiting {path}")


def file_key(url: str) -> str:
    """Accepts a full figma.com URL or a bare file key."""
    if "figma.com" not in url:
        return url
    parts = urllib.parse.urlparse(url).path.strip("/").split("/")
    # /design/<key>/<name>  or  /file/<key>/<name>
    for marker in ("design", "file", "proto"):
        if marker in parts:
            return parts[parts.index(marker) + 1]
    sys.exit(f"Could not find a file key in: {url}")


def walk(node, depth=0):
    yield node, depth
    for child in node.get("children", []):
        yield from walk(child, depth + 1)


def box(node):
    return node.get("absoluteBoundingBox") or {}


# --- commands ---------------------------------------------------------------

def cmd_frames(url: str):
    """List the top-level frames on every page, so you can pick one."""
    document = get(f"/files/{file_key(url)}?depth=2")["document"]
    for page in document.get("children", []):
        print(f"\n# {page.get('name')}")
        for frame in page.get("children", []):
            b = box(frame)
            size = f"{b.get('width', 0):.0f} x {b.get('height', 0):.0f}" if b else "-"
            print(f"  {frame.get('id'):<12} {size:>12}  {frame.get('name')}")


def cmd_layout(url: str, target: str):
    """Every layer inside a frame, positioned relative to that frame.

    These are the numbers a SwiftUI layout wants: divide by the frame's width
    and height and you have the fractions the screens are written in.
    """
    key = file_key(url)

    if ":" in target:
        # An id can be fetched on its own, which avoids pulling a file that may
        # be hundreds of frames wide just to read one screen.
        node_id = urllib.parse.quote(target)
        nodes = get(f"/files/{key}/nodes?ids={node_id}").get("nodes", {})
        entry = nodes.get(target) or (list(nodes.values())[0] if nodes else None)
        frame = entry.get("document") if entry else None
    else:
        document = get(f"/files/{key}")["document"]
        frame = next(
            (n for n, _ in walk(document) if n.get("name") == target), None
        )

    if frame is None:
        sys.exit(f"No layer named or with id {target!r}. Try: frames")

    origin = box(frame)
    fw, fh = origin.get("width", 0), origin.get("height", 0)
    print(f"frame {frame.get('name')!r}  {fw:.0f} x {fh:.0f}\n")
    print(f"{'id':<12} {'x':>7} {'y':>7} {'w':>7} {'h':>7}   {'x/W':>6} {'y/H':>6} {'w/W':>6}  name")

    for node, depth in walk(frame):
        if node is frame:
            continue
        b = box(node)
        if not b:
            continue
        x, y = b["x"] - origin["x"], b["y"] - origin["y"]
        w, h = b["width"], b["height"]
        print(
            f"{node.get('id'):<12} {x:7.1f} {y:7.1f} {w:7.1f} {h:7.1f}   "
            f"{x / fw:6.3f} {y / fh:6.3f} {w / fw:6.3f}  "
            f"{'  ' * depth}{node.get('name')}"
        )
        style = node.get("style")
        if style:
            print(
                f"{'':<12} {'':>31}   font {style.get('fontFamily')} "
                f"{style.get('fontPostScriptName') or ''} "
                f"{style.get('fontSize')}pt  tracking {style.get('letterSpacing')}"
            )
        for fill in node.get("fills", []):
            if fill.get("type") == "SOLID" and fill.get("visible", True):
                c = fill["color"]
                hexcode = "".join(f"{round(c[k] * 255):02X}" for k in ("r", "g", "b"))
                print(f"{'':<12} {'':>31}   fill #{hexcode}")
        for stroke in node.get("strokes", []):
            if stroke.get("type") == "SOLID" and stroke.get("visible", True):
                c = stroke["color"]
                hexcode = "".join(f"{round(c[k] * 255):02X}" for k in ("r", "g", "b"))
                print(f"{'':<12} {'':>31}   stroke #{hexcode} w{node.get('strokeWeight')}")


def cmd_export(url: str, node_id: str, asset: str):
    """Render one node at 2x and 3x straight into the drop folder.

    Saves them under the name the importer expects, so the whole run is:
    export, then Tools/import-art.sh.
    """
    key = file_key(url)
    DROP.mkdir(parents=True, exist_ok=True)

    for scale in (2, 3):
        query = urllib.parse.urlencode(
            {"ids": node_id, "format": "png", "scale": scale}
        )
        result = get(f"/images/{key}?{query}", use_cache=False)
        if result.get("err"):
            sys.exit(f"Figma could not render {node_id}: {result['err']}")
        link = (result.get("images") or {}).get(node_id)
        if not link:
            sys.exit(f"Figma returned no image for {node_id}")

        # The rendered PNG lives on a pre-signed S3 URL — no token on this one.
        with urllib.request.urlopen(link, timeout=120) as response:
            data = response.read()
        out = DROP / f"{asset}@{scale}x.png"
        out.write_bytes(data)
        print(f"  {out.relative_to(DROP.parent.parent)}  ({len(data) // 1024} KB)")

    print("\nNow run: Tools/import-art.sh")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    command, args = sys.argv[1], sys.argv[2:]
    handlers = {"frames": cmd_frames, "layout": cmd_layout, "export": cmd_export}
    if command not in handlers:
        sys.exit(__doc__)
    try:
        handlers[command](*args)
    except TypeError:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
