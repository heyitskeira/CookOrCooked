#!/usr/bin/env python3
"""
figma_export.py — bulk-export assets from a Figma file.

Stdlib only. No pip install needed.

    export FIGMA_TOKEN=figd_xxxxxxxx
    export FIGMA_FILE=abc123XYZ

    # 1. see what's in the file
    python3 figma_export.py list > nodes.tsv

    # 2. export everything whose layer name matches a pattern
    python3 figma_export.py export --match '^(icon|prop|char)-' --scales 1,2,3

    # 3. or export an explicit list of node ids
    python3 figma_export.py export --ids 12:34,56:78

    # 4. build ready-to-drop Xcode imagesets instead of loose files
    python3 figma_export.py export --match '^ui-' --scales 1,2,3 --imageset

Notes
  * A node renders with a transparent background unless the node itself has a
    fill. Pick the element/group, not the screen frame.
  * contents_only defaults to true, so overlapping siblings are excluded —
    which is exactly what you want for pulling one control off a busy screen.
  * Images expire after 30 days, so download promptly (this script does).
  * Max 32 megapixels per render; larger is silently scaled down.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

API = "https://api.figma.com/v1"
RENDERABLE = {"FRAME", "GROUP", "COMPONENT", "COMPONENT_SET", "INSTANCE",
              "VECTOR", "RECTANGLE", "ELLIPSE", "STAR", "LINE", "POLYGON",
              "BOOLEAN_OPERATION", "TEXT", "SECTION"}


# ---------------------------------------------------------------- http

def api(path, token, params=None, tries=6):
    url = API + path
    if params:
        url += "?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"X-Figma-Token": token})
    for n in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=180) as r:
                return json.load(r)
        except urllib.error.HTTPError as e:
            if e.code == 429:
                wait = int(e.headers.get("Retry-After") or min(60, 2 ** n))
                sys.stderr.write(f"  rate limited, waiting {wait}s\n")
                time.sleep(wait)
                continue
            if e.code >= 500 and n < tries - 1:
                time.sleep(2 ** n)
                continue
            body = e.read().decode("utf8", "replace")[:400]
            raise SystemExit(f"HTTP {e.code} on {path}\n{body}")
        except urllib.error.URLError as e:
            if n < tries - 1:
                time.sleep(2 ** n)
                continue
            raise SystemExit(f"network error: {e}")
    raise SystemExit("gave up after repeated rate limits")


def download(url, dest):
    for n in range(4):
        try:
            with urllib.request.urlopen(url, timeout=180) as r, open(dest, "wb") as f:
                f.write(r.read())
            return True
        except Exception:
            if n < 3:
                time.sleep(2 ** n)
    return False


# ---------------------------------------------------------------- tree

def walk(node, page="", trail=()):
    """Yield (id, name, type, page, breadcrumb, w, h) for every node."""
    t = node.get("type", "")
    if t == "CANVAS":
        page = node.get("name", "")
        trail = ()
    elif t != "DOCUMENT":
        box = node.get("absoluteBoundingBox") or {}
        yield (node.get("id", ""), node.get("name", ""), t, page,
               " / ".join(trail), box.get("width"), box.get("height"))
        trail = trail + (node.get("name", ""),)
    for child in node.get("children", []) or []:
        yield from walk(child, page, trail)


def slug(name):
    s = name.strip().lower()
    s = s.replace("&", " and ")
    s = re.sub(r"[^a-z0-9]+", "-", s).strip("-")
    return s or "unnamed"


def chunks(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


# ---------------------------------------------------------------- commands

def cmd_list(args, token):
    sys.stderr.write("fetching file tree...\n")
    doc = api(f"/files/{args.file}", token,
              {"depth": args.depth} if args.depth else None)["document"]
    rows = list(walk(doc))
    print("id\tname\ttype\tpage\tpath\twidth\theight")
    for nid, name, typ, page, path, w, h in rows:
        if args.match and not re.search(args.match, name):
            continue
        if args.renderable_only and typ not in RENDERABLE:
            continue
        print(f"{nid}\t{name}\t{typ}\t{page}\t{path}\t"
              f"{'' if w is None else round(w)}\t{'' if h is None else round(h)}")
    sys.stderr.write(f"{len(rows)} nodes in file\n")


def resolve_targets(args, token):
    """-> list of (node_id, filename_slug)"""
    if args.ids:
        ids = [i.strip() for i in args.ids.split(",") if i.strip()]
        sys.stderr.write("looking up names...\n")
        data = api(f"/files/{args.file}/nodes", token,
                   {"ids": ",".join(ids), "depth": 1})["nodes"]
        out = []
        for nid in ids:
            entry = data.get(nid)
            name = entry["document"]["name"] if entry else nid
            out.append((nid, slug(name)))
        return out

    sys.stderr.write("fetching file tree...\n")
    doc = api(f"/files/{args.file}", token)["document"]
    pat = re.compile(args.match) if args.match else None
    seen, out = {}, []
    for nid, name, typ, page, path, w, h in walk(doc):
        if typ not in RENDERABLE:
            continue
        if args.pages and page not in args.pages.split(","):
            continue
        if pat and not pat.search(name):
            continue
        base = slug(name)
        seen[base] = seen.get(base, 0) + 1
        if seen[base] > 1:
            base = f"{base}-{seen[base]}"
        out.append((nid, base))
    return out


def cmd_export(args, token):
    targets = resolve_targets(args, token)
    if not targets:
        raise SystemExit("nothing matched — run `list` first to check names")

    scales = [float(s) for s in args.scales.split(",")]
    os.makedirs(args.out, exist_ok=True)
    sys.stderr.write(f"{len(targets)} nodes x {len(scales)} scale(s) "
                     f"-> {args.out}\n")

    by_id = dict(targets)
    ok = fail = 0
    for scale in scales:
        tag = "" if scale == 1 else f"@{int(scale)}x"
        for batch in chunks([t[0] for t in targets], args.batch):
            res = api(f"/images/{args.file}", token, {
                "ids": ",".join(batch),
                "format": args.format,
                "scale": scale,
                "use_absolute_bounds": str(args.absolute_bounds).lower(),
                "contents_only": str(not args.include_overlaps).lower(),
            })
            for nid, url in (res.get("images") or {}).items():
                name = by_id.get(nid, nid.replace(":", "-"))
                if not url:
                    sys.stderr.write(f"  ! no render: {name} ({nid})\n")
                    fail += 1
                    continue
                if args.imageset:
                    d = os.path.join(args.out, f"{name}.imageset")
                    os.makedirs(d, exist_ok=True)
                    dest = os.path.join(d, f"{name}{tag}.{args.format}")
                else:
                    dest = os.path.join(args.out, f"{name}{tag}.{args.format}")
                if download(url, dest):
                    ok += 1
                    sys.stderr.write(f"  {os.path.relpath(dest, args.out)}\n")
                else:
                    fail += 1
                    sys.stderr.write(f"  ! download failed: {name}\n")

    if args.imageset:
        write_imageset_json(args, scales, [n for _, n in targets])

    sys.stderr.write(f"\ndone: {ok} written, {fail} failed\n")


def write_imageset_json(args, scales, names):
    for name in names:
        d = os.path.join(args.out, f"{name}.imageset")
        if not os.path.isdir(d):
            continue
        images = []
        for s in (1.0, 2.0, 3.0):
            entry = {"idiom": "universal", "scale": f"{int(s)}x"}
            if s in scales:
                tag = "" if s == 1 else f"@{int(s)}x"
                fn = f"{name}{tag}.{args.format}"
                if os.path.exists(os.path.join(d, fn)):
                    entry["filename"] = fn
            images.append(entry)
        with open(os.path.join(d, "Contents.json"), "w") as f:
            json.dump({"images": images,
                       "info": {"author": "xcode", "version": 1}}, f, indent=2)


# ---------------------------------------------------------------- cli

def main():
    p = argparse.ArgumentParser(description=__doc__,
                                formatter_class=argparse.RawDescriptionHelpFormatter)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--file", default=os.environ.get("FIGMA_FILE"),
                        help="Figma file key (or set FIGMA_FILE)")
    sub = p.add_subparsers(dest="cmd", required=True)

    pl = sub.add_parser("list", parents=[common], help="dump the node tree as TSV")
    pl.add_argument("--match", help="regex filter on layer name")
    pl.add_argument("--depth", type=int, help="stop traversal at this depth")
    pl.add_argument("--renderable-only", action="store_true")

    pe = sub.add_parser("export", parents=[common], help="render and download nodes")
    pe.add_argument("--ids", help="explicit comma-separated node ids")
    pe.add_argument("--match", help="regex filter on layer name")
    pe.add_argument("--pages", help="comma-separated page names to limit to")
    pe.add_argument("--format", default="png", choices=["png", "jpg", "svg", "pdf"])
    pe.add_argument("--scales", default="2", help="e.g. 1,2,3 (png/jpg only)")
    pe.add_argument("--out", default="figma-export")
    pe.add_argument("--batch", type=int, default=50, help="node ids per request")
    pe.add_argument("--imageset", action="store_true",
                    help="write .imageset folders with Contents.json")
    pe.add_argument("--absolute-bounds", action="store_true",
                    help="don't crop to visible content")
    pe.add_argument("--include-overlaps", action="store_true",
                    help="render content that overlaps the node (slower)")

    args = p.parse_args()

    token = os.environ.get("FIGMA_TOKEN")
    if not token:
        raise SystemExit("set FIGMA_TOKEN (Figma > Settings > Security > "
                         "Personal access tokens; needs file_content:read)")
    if not args.file:
        raise SystemExit("set --file or FIGMA_FILE (the key from the file URL: "
                         "figma.com/design/<KEY>/<name>)")

    {"list": cmd_list, "export": cmd_export}[args.cmd](args, token)


if __name__ == "__main__":
    main()
