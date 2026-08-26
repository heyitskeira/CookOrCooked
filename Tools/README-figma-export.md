# Bulk-exporting assets from Figma

Three options, cheapest first.

## 1. Figma's own bulk export (no setup, still manual-ish)

In the Figma file: select the layers you want → in the right panel, **Export** → `+`
→ pick PNG and add `2x` / `3x` rows → then **File → Export…** (`⇧⌘E`) exports every
layer that has export settings, in one go.

Good enough if you only do it once. The catch is you still click through 54 layers
to add export settings, and you redo it whenever the design changes.

## 2. `figma_export.py` (this folder) — REST API, repeatable

Stdlib only, no `pip install`.

### Setup

1. **Token** — Figma → your avatar → Settings → Security → *Personal access tokens*
   → generate one with the `file_content:read` scope. Starts with `figd_`.
2. **File key** — from the URL `figma.com/design/<FILE_KEY>/Cook-or-Cooked`.

```bash
export FIGMA_TOKEN=figd_xxxxxxxxxxxx
export FIGMA_FILE=xxxxxxxxxxxxxxxxxx
```

### See what's in the file

```bash
python3 Tools/figma_export.py list --renderable-only > nodes.tsv
```

Columns: `id · name · type · page · path · width · height`. Open it in a spreadsheet
and find the layers you want. This is also how you get node ids for `--ids`.

### Export

```bash
# everything whose layer name starts with a category prefix
python3 Tools/figma_export.py export \
  --match '^(icon|prop|char|ui|bg)-' \
  --scales 1,2,3 \
  --out Asset-Final/exported

# just one page
python3 Tools/figma_export.py export --pages "Components" --scales 2

# explicit node ids
python3 Tools/figma_export.py export --ids 12:34,56:78

# vectors as SVG instead
python3 Tools/figma_export.py export --match '^icon-' --format svg
```

### Straight into Xcode

```bash
python3 Tools/figma_export.py export \
  --match '^(ui|icon)-' --scales 1,2,3 --imageset \
  --out Cooked/Assets.xcassets
```

`--imageset` writes proper `.imageset` folders with a generated `Contents.json`
wiring up @1x/@2x/@3x — drop-in ready, no manual asset-catalog work.

### Useful flags

| Flag | Why |
|---|---|
| `--include-overlaps` | By default Figma excludes anything overlapping the node. Turn this on only if a crop looks wrong. |
| `--absolute-bounds` | Keeps the node's full frame instead of cropping to visible pixels. Useful for text. |
| `--batch N` | Node ids per request (default 50). Lower it if you hit timeouts on huge nodes. |
| `--format svg` | Vectors stay vectors. |

## 3. The Figma connector

This workspace has a Figma connector available, but it needs authorising before it
can be used — connect it in your Claude connector settings. Once it's live, Claude
can read the file directly and you can skip the token setup.

---

## Getting transparent PNGs (the thing that matters here)

The API renders **whatever node you point at, in isolation**. So:

- Point at the **element or group**, not the screen frame. A frame with a forest
  background fill renders *with* the forest.
- `contents_only` is on by default, so overlapping siblings are excluded — this is
  what lets you pull `action-button-pill` off a busy station screen cleanly.
- If a layer renders empty, it's invisible or at 0% opacity in Figma. The API
  returns `null` for it and the script logs `! no render`.

## Naming

Filenames come from Figma layer names, lowercased and kebab-cased
(`Timer / Alarm Clock` → `timer-alarm-clock`). Duplicates get `-2`, `-3` suffixes.

**Rename the layers in Figma to the target names first** — the ones in
`Asset-Final/MISSING-ASSETS.md`. Then the export lands correctly named and you
never touch filenames by hand again.

## Limits

- Rate limited; the script backs off and retries on 429 automatically.
- Render URLs expire after 30 days — the script downloads immediately, so this
  only matters if you save the JSON and come back later.
- Max 32 megapixels per render; anything larger is silently scaled down.

Sources: [Figma file endpoints](https://developers.figma.com/docs/rest-api/file-endpoints/),
[personal access tokens](https://developers.figma.com/docs/rest-api/personal-access-tokens/)
