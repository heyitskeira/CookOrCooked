# Runbook — from Figma to Xcode

Getting the 65 missing assets out of Figma and into the app. Follow in order;
Step 1 is a go/no-go gate, don't skip it.

Current state: 126 organised files in `Asset-Final/`, 65 assets still needed,
each with a reference crop in `Asset-Final/_missing-refs/` and a row in
`Asset-Final/MISSING-ASSETS.md`.

---

## Step 1 — Check the screens are actually layered (5 min, do this first)

Everything below assumes your Figma file contains *editable layers*. If the
screens were placed into Figma as flat PNGs, there is nothing to extract and the
rest of this runbook is void.

**How to check:** open a screen frame — say the kitchen screen — and try to click
the timer clock in the top-right. Then look at the layers panel.

| What you see | Verdict |
|---|---|
| A tree of named layers; clicking selects the clock alone | ✅ Go. Continue to Step 2. |
| One image layer filling the frame; clicking selects the whole screen | ❌ Stop. |

If it's ❌, the layered source lives with whoever drew it. Ask them for the
working file, or for the 65 assets exported directly — send them
`Asset-Final/asset-gaps.html`, it shows exactly what's needed.

A faster check once you've done Step 4:

```bash
python3 Tools/figma_export.py list --renderable-only | wc -l
```

A properly layered file will return thousands of nodes. A few hundred means the
screens are mostly flat.

---

## Step 2 — Build an export page in Figma

Don't export from the screen frames directly. Elements there sit on backgrounds,
overlap each other, and get renamed as the design moves. Make a dedicated page
where each asset is one cleanly-named layer.

**Create the page:** in the left panel, `+` next to Pages → name it `⚙ Export`.
Leading symbol keeps it sorted away from your design pages.

**Layout inside the page** — 7 sections, one per category, stacked top to bottom.
Press `S` for the Section tool (or Shift+S) and draw one per category:

| Section name | Assets | Suggested cell |
|---|---|---|
| `A · HUD` | 20 | 400 × 400 |
| `B · Signage` | 5 | 600 × 600 |
| `C · Characters` | 8 | 600 × 800 |
| `D · Props` | 12 | 500 × 500 |
| `E · Backgrounds` | 5 | 1748 × 804 (half-size screens) |
| `F · Recipe book` | 12 | 500 × 500 |
| `G · Status icons` | 3 | 300 × 300 |

Inside each section lay items on a grid, 8 per row, 80px gutter, 200px between
sections. Exact numbers don't matter — the API crops to visible pixels, so
spacing is purely for your own sanity.

> Cell size is a *guide for eyeballing*, not a constraint. Don't scale artwork to
> fit a cell; that bakes the wrong resolution in. Paste at native size.

---

## Step 3 — Move each asset onto the page

For each row in `MISSING-ASSETS.md`:

1. Open the screen named in the **Appears on screen** column.
2. Select the element. Double-click to drill into groups, or `⌘`-click to hit a
   nested layer directly.
3. Cross-check against `Asset-Final/_missing-refs/<name>.png` so you grab the
   right thing.
4. `⌘C`, switch to `⚙ Export`, `⌘V`. Paste onto bare canvas or into an unfilled
   frame — **never onto a filled background**.
5. Rename the pasted layer to **exactly** the name from the Asset column.

**Naming is the whole game.** The exporter derives filenames from layer names, so
`Timer / Alarm Clock` becomes `timer-alarm-clock.png` automatically. Get the names
right here and you never touch a filename by hand.

Two Figma features worth using:

- **Bulk rename** — select several layers, right-click → *Rename layers* (`⌘R`).
  Supports find/replace and auto-numbering. Good for the step-icon and leaf sets.
- **Components** (`⌥⌘K`) — optional, but makes assets reusable in the design file
  and easier to track later. Doesn't change how the export works.

### Checking transparency as you go

Click a pasted layer and look behind it. If you see the Figma canvas grid, you're
fine. If you see forest, you dragged a background rectangle along — delete it from
the pasted copy.

---

## Step 4 — Special cases

Seven of the 65 don't follow the simple copy-paste path.

**Backgrounds (`bg-*`, 5 assets).** These *are* the screen frame, minus the UI.
Duplicate the screen frame onto `⚙ Export`, delete every UI layer from the copy,
leave only the scene art, rename the frame. Export the frame, not a group.

**`char-group-all` → bear and beaver.** Both animals appear only in the welcome
group illustration. If it's a single flattened illustration, they can't be
separated and you'll need them redrawn. Check before promising the waiting room
supports 6 avatars — right now only 4 are separable (`char-squirrel`,
`char-raccoon`, `char-rabbit`, `char-fox`).

**`station-name-plaque-left` / `-right`.** Mirrored versions of the same ribbon.
Export one and flip it in SwiftUI (`.scaleEffect(x: -1)`) rather than shipping
two files — unless the shading differs, in which case export both.

**`recipe-leaf-decor-set`.** The crop is a contact sheet of 11 different foliage
sprites, one per recipe step — a reference, not a shippable asset. Name the 11
individually: `recipe-leaf-01` … `recipe-leaf-11`. Your final count goes 65 → 75.

**`recipe-step-icons` / `recipe-step-icons-07-11`.** Same deal — 11 distinct
badges, currently captured as two column crops. Split into `recipe-step-icon-01`
… `-11`.

**`prop-chopping-board` vs `prop-chopping-board-large`.** Two sizes of the same
object. If the art is identical, export only the large one and scale down in code.

**`prop-skillet` vs `utensil-saucepan`.** Different artwork despite similar shape.
Export both.

---

## Step 5 — Get your token and file key

**Token:** Figma → avatar (top-right) → Settings → Security tab → *Personal access
tokens* → *Generate new token*. Give it the `file_content:read` scope. Copy it
immediately, it's shown once. Starts with `figd_`.

**File key:** from the file URL —
`figma.com/design/`**`ABC123xyz`**`/Cook-or-Cooked` — the middle segment.

```bash
export FIGMA_TOKEN=figd_your_token_here
export FIGMA_FILE=ABC123xyz
```

Add these to `~/.zshrc` if you want them to persist. **Don't commit the token** —
it grants read access to every file you can see.

---

## Step 6 — Dry run

Never export blind. List first:

```bash
python3 Tools/figma_export.py list --renderable-only > /tmp/nodes.tsv
grep -c . /tmp/nodes.tsv
```

Then confirm your export page is complete:

```bash
python3 Tools/figma_export.py list --match '^(ui|icon|prop|char|bg|recipe|tab|step|action|kitchen|avatar|name|text|player|signpost|mossy|ivy|station|timer|help|carousel|settings|paw|banner|hint|plus)-'
```

You want ~75 rows back. Fewer means layers are missing or misnamed — fix in Figma
and re-run. This costs nothing and saves a bad export.

---

## Step 7 — Export

```bash
python3 Tools/figma_export.py export \
  --pages "⚙ Export" \
  --scales 1,2,3 \
  --out Asset-Final/exported
```

`--pages` scopes it to your export page so nothing else leaks in. Three scales
because iOS wants @1x/@2x/@3x. Expect ~225 files (75 assets × 3).

Takes a few minutes; the script logs each file and backs off automatically if
Figma rate-limits it.

SVG instead, for flat vector icons:

```bash
python3 Tools/figma_export.py export --pages "⚙ Export" --match '^icon-' --format svg --out Asset-Final/exported-svg
```

---

## Step 8 — Verify

```bash
pip3 install pillow          # once, enables the pixel checks
python3 Tools/verify_export.py Asset-Final/exported
```

Reports four things:

| Finding | What it means |
|---|---|
| `MISSING` | On the list, not in the export — layer missing or misnamed in Figma |
| `NOT ON THE LIST` | Exported but unexpected — almost always a typo in the layer name |
| `INCONSISTENT SCALES` | Some assets lack an @2x or @3x |
| `PIXEL WARNINGS` | No transparent pixels (you exported a frame not an element), or a suspiciously tiny render |

Exit code is 1 if anything's missing, so you can gate a script on it.

Then eyeball them — open `Asset-Final/exported` in Finder, switch to Gallery view,
and compare against `Asset-Final/asset-gaps.html` side by side.

---

## Step 9 — Install into Xcode

Once the export is clean, re-run pointing at the asset catalog:

```bash
python3 Tools/figma_export.py export \
  --pages "⚙ Export" --scales 1,2,3 --imageset \
  --out Cooked/Assets.xcassets
```

`--imageset` writes real `.imageset` folders with a generated `Contents.json`
wiring @1x/@2x/@3x. Then in Xcode: **File → Add Files to "Cooked"…**, or just open
the asset catalog — it picks up folders added on disk.

Keep `Asset-Final/exported/` as your archive. It's the reviewed source of truth;
the catalog is the build artifact.

### Sanity check in Xcode

1. Open `Assets.xcassets` — each new imageset should show three filled slots.
2. Empty slot = a scale didn't export. Re-run for that asset.
3. Build. Missing-asset failures surface at runtime as blank images, not compile
   errors, so run the app and click through the flow.

---

## Step 10 — Wire them up

Priority order, by how much they unblock:

1. **HUD** (20) — on nearly every screen
2. **Characters** (8) — `Kitchen/HandsNode.swift` already expects `paw-hands`
3. **Signage** (5) — the whole pre-game flow
4. **Props** (12) — the kitchen map in `Kitchen/KitchenScene.swift`
5. **Backgrounds, recipe book, status icons** (20)

In SwiftUI: `Image("timer-alarm-clock")`. In SpriteKit:
`SKSpriteNode(imageNamed: "prop-stove")`.

---

## Housekeeping

- `Asset-Final/_unused/` (59 files) — safe to delete, **except**
  `_unused/junk/blank-frame.png`, which is the dashed drop-zone target from the
  station screens. Move it to `UI/ui-drop-zone-frame.png` first.
- `Asset-Final-BACKUP-20260826/` (433 MB) — delete once you're happy the
  reorganisation is right.
- `Asset-Final/_missing-refs/` — keep until every asset is exported, then delete.
  It's reference material, not shippable art.
- Add `.env` or your shell exports to `.gitignore` so the Figma token never lands
  in the repo.

## If something goes wrong

| Symptom | Cause |
|---|---|
| `HTTP 403` | Token expired, or missing `file_content:read` scope |
| `HTTP 404` | Wrong file key — re-copy from the URL |
| `! no render: <name>` | Layer is hidden or at 0% opacity in Figma |
| Export has forest baked in | You exported a frame with a fill; export the child element instead |
| Everything is tiny | `--scales` wasn't passed, defaulted to 2 |
| Names come out as `group-47` | Layers weren't renamed in Figma — go back to Step 3 |
