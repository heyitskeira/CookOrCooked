"""
Punch the photo windows out of the designed strip templates.

Two passes:
  1. Flood-fill the pure-white window rectangles to alpha 0.
  2. Grow that hole outward into the near-white *cutout stroke* the designer
     drew around the animal group. That stroke reads as a white halo once a
     photo sits behind it, so it has to go — but only where it touches a
     window. Growth is confined to the window rectangle, so white artwork
     that merely sits nearby (the shortcake's cream, the flour pile) is
     never reached.
"""
from PIL import Image, ImageFilter
import numpy as np, glob, json
from collections import deque

WHITE_WINDOW = 246   # a window pixel is this white or whiter
WHITE_STROKE = 218   # the cutout stroke is softer; grow into anything this pale
GROW_MARGIN  = 4     # px the growth may spill past the window rect

out = {}
for f in sorted(glob.glob("Photobooth/assets/_source/photostrip-originals/*.png")):
    key = "strip-" + f.split("/")[-1].split(".")[0]
    src = Image.open(f).convert("RGBA")
    a   = np.array(src)
    rgb = a[:, :, :3].astype(int)
    H, W, _ = rgb.shape
    mn  = rgb.min(axis=2)

    # ---- pass 1: the windows themselves ----
    white = mn >= WHITE_WINDOW
    seen  = np.zeros((H, W), bool)
    mask  = np.zeros((H, W), bool)
    boxes = []
    for y in range(0, H, 2):
        for x in range(0, W, 2):
            if white[y, x] and not seen[y, x]:
                q = deque([(y, x)]); seen[y, x] = True; px = []
                while q:
                    cy, cx = q.popleft(); px.append((cy, cx))
                    for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
                        ny, nx = cy+dy, cx+dx
                        if 0 <= ny < H and 0 <= nx < W and white[ny,nx] and not seen[ny,nx]:
                            seen[ny,nx] = True; q.append((ny,nx))
                if len(px) > 20000:
                    p = np.array(px)
                    mask[p[:,0], p[:,1]] = True
                    ys, xs = p[:,0], p[:,1]
                    boxes.append([int(xs.min()), int(ys.min()),
                                  int(xs.max()-xs.min()+1), int(ys.max()-ys.min()+1)])
    boxes.sort(key=lambda b: b[1])

    # Props bite into some windows, shrinking the measured box. Every window on
    # a strip is the same size, so grow each back to the largest measured size
    # about its own centre, then pad. Photos sit *under* the template, so
    # over-covering is invisible; under-covering would show a gap.
    mw = max(b[2] for b in boxes); mh = max(b[3] for b in boxes); PAD = 6
    rects = []
    for x, y, w, h in boxes:
        cx, cy = x + w/2, y + h/2
        rects.append([round(cx-mw/2)-PAD, round(cy-mh/2)-PAD, mw+PAD*2, mh+PAD*2])

    # ---- pass 2: eat the cutout stroke inside each window ----
    inside = np.zeros((H, W), bool)
    for x, y, w, h in rects:
        y0, y1 = max(0, y-GROW_MARGIN), min(H, y+h+GROW_MARGIN)
        x0, x1 = max(0, x-GROW_MARGIN), min(W, x+w+GROW_MARGIN)
        inside[y0:y1, x0:x1] = True

    candidate = (mn >= WHITE_STROKE) & inside & ~mask
    q = deque()
    ys, xs = np.where(mask & inside)
    for y, x in zip(ys, xs):
        q.append((y, x))
    grown = 0
    while q:
        cy, cx = q.popleft()
        for dy, dx in ((1,0),(-1,0),(0,1),(0,-1)):
            ny, nx = cy+dy, cx+dx
            if 0 <= ny < H and 0 <= nx < W and candidate[ny,nx] and not mask[ny,nx]:
                mask[ny,nx] = True; grown += 1; q.append((ny,nx))

    m = Image.fromarray((mask*255).astype('uint8')).filter(ImageFilter.GaussianBlur(0.8))
    a[:, :, 3] = np.clip(255 - np.array(m).astype(int), 0, 255).astype('uint8')
    Image.fromarray(a).save(f"Photobooth/assets/strips/{key}.png", optimize=True)

    out[key] = {"w": W, "h": H, "windows": rects}
    print(f"{key}: windows {mw}x{mh} {rects}  | stroke pixels cleared: {grown}")

json.dump(out, open("Photobooth/assets/strips/strips.json", "w"), indent=2)
