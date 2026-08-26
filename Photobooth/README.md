# Photobooth

A browser photobooth for demo days, dressed in the game's own art. Guests
step up, get a three-shot strip in a woodland frame, garnish it with the
chefs and utensils from the kitchen, and download a 2× PNG.

## Running it

```bash
cd Photobooth
./start.sh            # serves on http://localhost:8080 and opens it
./start.sh 9000       # or pick another port
```

The camera is the reason for the server. Browsers only hand out
`getUserMedia` on a secure origin, and `file://` doesn't count — `localhost`
does, with no certificate and no internet. Opening `index.html` directly
still works for the upload path and the whole editor; only the live webcam
is unavailable, and the page says so.

On first run the browser asks for camera permission. Grant it once and the
booth is ready for the day.

## The flow

1. **Set the table** — strip design, countdown (instant/3s/5s), and whether
   the preview mirrors like a selfie. A designed strip fixes its own shot
   count, so the shots control only appears for the plain frames.
2. **Shoot** — a clock counts down over the live feed, the screen flashes,
   and each frame is centre-cropped to the window shape. No camera?
   *Upload photos* takes the same path.
3. **Garnish** — tap a sticker to drop it on, drag to move, the corner knob
   resizes *and* spins, the red knob bins it.
4. **Serve it up** — downloads `cook-or-cooked-<timestamp>.png`. Designed
   strips export at their native 700×1712, which is roughly 300dpi on a
   2.3×5.7in print; the plain frames export at 1800px wide.

## Strip designs

The three designed strips are the main event:

| Design | Shots | Look |
|---|---|---|
| Paw Prints | 4 | grid paper, muddy paws, `#TEAMCOOKED` |
| The Crew | 3 | brown card, `#COOKORCOOKED`, the animals along the bottom |
| Kitchen Mess | 3 | speckled brown, big logo, ruined shortcake and spilt flour |

Four plainer frames — Forest Clearing, Stone Slab, Wood Planks, Cream &
Tomato — are drawn in canvas and carry an editable caption line and the date.

### How the designed strips work

The originals are opaque PNGs with white rectangles where the photos go.
`tools-punch-windows.py` flood-fills those windows to transparent, so the app
can draw photos *underneath* the strip art. That ordering is what keeps the
paws, the bear, the cake and the flour pile in front of the photos instead of
being painted over by them.

The script makes a second pass that matters: the animal group is drawn with a
white cutout stroke around it, and where that stroke crosses a window it used
to survive as a white halo around the bear once a photo was behind it. The
pass grows the punched hole into that stroke, but only inside the window
rectangle — so white artwork that merely sits nearby, like the shortcake's
cream and the flour pile, is never touched.

Re-run it after editing any source strip:

```bash
python3 tools-punch-windows.py
```

Window rectangles live in `assets/strips/strips.json` **and** are baked into
`FRAMES` in `index.html`. The JS copy is the one that runs — `fetch()` is
blocked on `file://` pages, so the geometry can't be loaded at runtime. The
JSON is the record of where the numbers came from; if you re-punch the
templates, copy the new numbers across.

### The QR code

`assets/ui/qr.png` is drawn into the design's corner placeholder at render
time — 70×70 on Paw Prints (top left) and on the other two (top right). It is
re-rendered from the supplied code at exactly 2px per module with a 3-module
quiet zone, so it lands 1:1 in the box with smoothing off and every module
stays a hard square.

**It is small.** 29 modules at 2px each is about as tight as a QR gets. On a
phone screen it should scan; printed at 70px on a 2.3in strip each module is
roughly 0.007in, which is below what print scanning normally tolerates. If the
strips are going to paper, the placeholder box wants to be bigger —
`assets/ui/qr-large.png` (740×740) is ready for that, and only the `qr:` rect
in `FRAMES` needs to change.

To point the code somewhere else, replace `qr.png` with a code rendered at the
same 2px-per-module scale, or swap `QR_SRC` in `index.html`.

## Assets

`assets/` is a downscaled copy of art already in the game — pulled from
`Cooked/Assets.xcassets` and `Assets-agung/`, then resized (stickers to
420px, frames to 1400px) so the page loads fast on a kiosk machine.

```
assets/
  strips/     the three designed strips, windows punched to alpha
  stickers/   everything the garnish tray offers
  frames/     backdrops for the drawn frames
  overlays/   grid-paper and sprinkle textures, unused by the app so far
  ui/         logo, clock, the animal group, the QR code
  _source/    the untouched folders these were built from
```

Nothing here is generated art: the chefs, paws, ingredients, utensils, logo
and clock are the same files the app ships. Colours in `index.html` are
copied from `Cooked/Theme.swift`, so if the palette moves in the game it
should move here too.

To add a sticker, drop a transparent PNG in `assets/stickers/` and add its
filename (without `.png`) to the `TRAY` object near the top of the script.

## If *Serve it up* does nothing

Almost always the page was opened straight from disk. On a `file://` page the
browser treats every loaded image as foreign, which permanently taints the
canvas — the strip still renders on screen, but the browser refuses to export
it, so no file is ever produced. The studio warns about this on arrival and
the button reports it if you press anyway.

The fix is the same one the camera needs: run `./start.sh` and work from
`http://localhost:8080`.

If it fails on localhost, the button prints the actual error next to it —
that message is the thing to go on.

## Notes

- Everything runs client-side. No uploads, no network calls, no analytics —
  photos never leave the machine.
- Tested layout is responsive down to phone width, but the booth is meant
  for a laptop or tablet in landscape.
