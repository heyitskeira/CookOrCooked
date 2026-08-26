#!/usr/bin/env python3
"""
figma.py — read layout numbers and pull PNGs straight out of a Figma file.

Works on a free Figma account: the REST API needs only a personal access token,
not Dev Mode or a paid seat.

    Tools/figma.py frames <file-url>
    Tools/figma.py layout <file-url> <frame-id> [<frame-id> ...]
    Tools/figma.py export <file-url> <node-id>=<asset-name> [...]

Add --refresh to ignore the cache after the design has actually changed.

Batch aggressively: several frames in one `layout`, several drawings in one
`export`. Figma rate-limits reads hard, and one request for six screens is the
difference between reading a whole flow and being cut off half way.

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
# No expiry: a design file only changes when somebody edits it, and `--refresh`
# is how you say that happened. Re-reading a frame you already pulled is the
# single easiest way to burn the rate limit for nothing.
REFRESH = False
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
    if use_cache and not REFRESH and slot.exists():
        return json.loads(slot.read_text())

    request = urllib.request.Request(f"{API}{path}", headers={"X-Figma-Token": token()})
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=60) as response:
                payload = json.load(response)
            # Only cache what is safe to replay. Render responses hand back
            # short-lived S3 links, so storing them would mean serving dead
            # URLs back later.
            if use_cache:
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


def cmd_layout(url: str, *targets: str):
    """Every layer inside a frame, positioned relative to that frame.

    These are the numbers a SwiftUI layout wants: divide by the frame's width
    and height and you have the fractions the screens are written in.
    """
    key = file_key(url)
    if not targets:
        sys.exit("Give at least one frame id or name.")

    frames = []
    ids = [t for t in targets if ":" in t]
    names = [t for t in targets if ":" not in t]

    if ids:
        # The nodes endpoint takes a whole list, so six screens cost one request
        # rather than six. This is the difference between reading a flow in one
        # go and being rate limited half way through it.
        joined = urllib.parse.quote(",".join(ids))
        nodes = get(f"/files/{key}/nodes?ids={joined}").get("nodes", {})
        for node_id in ids:
            entry = nodes.get(node_id)
            if entry and entry.get("document"):
                frames.append(entry["document"])
            else:
                print(f"! no node {node_id}", file=sys.stderr)

    if names:
        document = get(f"/files/{key}")["document"]
        by_name = {n.get("name"): n for n, _ in walk(document)}
        for name in names:
            if name in by_name:
                frames.append(by_name[name])
            else:
                print(f"! no layer named {name!r}", file=sys.stderr)

    if not frames:
        sys.exit("Nothing matched. Try: frames")

    for index, frame in enumerate(frames):
        if index:
            print("\n" + "=" * 78 + "\n")
        dump_frame(frame)


def dump_frame(frame):
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


def cmd_export(url: str, *pairs: str):
    """Render nodes at 2x and 3x straight into the drop folder.

        figma.py export <url> 838:555=ui-waiting-rock 586:5758=ui-chef-1 ...

    Every node in one request per scale, so twenty drawings cost two calls
    rather than forty. Then: Tools/import-art.sh
    """
    key = file_key(url)
    DROP.mkdir(parents=True, exist_ok=True)

    wanted = {}
    for pair in pairs:
        if "=" not in pair:
            sys.exit(f"Expected <node-id>=<asset-name>, got {pair!r}")
        node_id, asset = pair.split("=", 1)
        wanted[node_id.strip()] = asset.strip()
    if not wanted:
        sys.exit("Give at least one <node-id>=<asset-name> pair.")

    for scale in (2, 3):
        query = urllib.parse.urlencode(
            {"ids": ",".join(wanted), "format": "png", "scale": scale}
        )
        result = get(f"/images/{key}?{query}", use_cache=False)
        if result.get("err"):
            sys.exit(f"Figma could not render: {result['err']}")

        images = result.get("images") or {}
        for node_id, asset in wanted.items():
            link = images.get(node_id)
            if not link:
                print(f"  ! no image for {node_id} ({asset})", file=sys.stderr)
                continue
            # The PNG lives on a pre-signed S3 URL — no token on this one.
            with urllib.request.urlopen(link, timeout=120) as response:
                data = response.read()
            out = DROP / f"{asset}@{scale}x.png"
            out.write_bytes(data)
            print(f"  {out.name}  ({len(data) // 1024} KB)")

    print("\nNow run: Tools/import-art.sh")


def main():
    global REFRESH
    argv = [a for a in sys.argv[1:] if a != "--refresh"]
    REFRESH = "--refresh" in sys.argv
    if not argv:
        sys.exit(__doc__)
    command, args = argv[0], argv[1:]
    handlers = {"frames": cmd_frames, "layout": cmd_layout, "export": cmd_export}
    if command not in handlers:
        sys.exit(__doc__)
    try:
        handlers[command](*args)
    except TypeError:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
