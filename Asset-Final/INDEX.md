# Asset-Final — Index

Two imports, one tree:

| Import | Date | Files | What it was |
|---|---|---|---|
| `art direction/` | 2026-08-26 | 185 | Figma board scrape — mostly flattened screen mockups |
| `cook or cooked assets/` | 2026-08-26 | 115 | Clean transparent-PNG asset drop |
| `missed in round 1/` | 2026-08-26 | 11 | Follow-up drop — 9 new sprites, 2 duplicates. Folder now empty; see `MISSING-ASSETS.md` |
| loose PNGs at project root | 2026-08-26 | 53 | Third drop — 18 new (plaque-free props + name plates), 34 duplicates, 1 higher-res replacement. Root now clean |

Both raw exports are preserved untouched at `../Asset-Final-BACKUP-20260826/`.

```
Asset-Final/
├── Assets-By-Screen/   158 shippable PNGs, grouped by the screen that uses them
├── Screens/             91 full-screen mockups (design reference, not shipped)
├── _missing-refs/       65 cropped references for assets still not exported
├── _unused/             83 duplicates, junk and superseded files — safe to delete
├── INDEX.md             ← you are here
├── MISSING-ASSETS.md    what still needs exporting from Figma
├── DESIGN-NOTES.md      transcribed Figma sticky notes (audio spec, sizing rules)
└── asset-gaps.html      visual gallery of the gaps
```

---

## Naming convention

Every filename is **globally unique and self-describing** — the name alone tells
you what the asset is, with no folder context needed. This matters because
`Assets.xcassets` is a flat namespace: you can drag any file straight in without
renaming or collisions. It also means an asset can be **swapped by overwriting
one file**, and moved between folders without breaking anything.

```
<category>-<subject>[-<variant>].png
```

All lowercase kebab-case, matching the existing `Cooked/Assets.xcassets`
(`back-button`, `create-kitchen`). **Folders are for browsing only — nothing
depends on them.**

| Prefix | Meaning | Count |
|---|---|---|
| `bg-` | full-bleed background plate (1748 × 804) | 5 |
| `panel-` | stone slab / panel that UI sits on | 3 |
| `station-` | kitchen-map prop, name plaque attached (+ the blank plank) | 10 |
| `label-` | station name lettering, no plank behind it | 10 |
| `prop-` | scene furniture, plaque-free (oven, stove, rack, board, bowl, bench, cabinet, bin, table) | 13 |
| `char-` | animal character, full body | 7 |
| `paw-` | first-person paws (bottom-right of station screens) | 6 |
| `btn-` | button or signpost | 6 |
| `hud-` | persistent in-game chrome | 1 |
| `header-` | wide banner header | 1 |
| `book-` | recipe book element | 2 |
| `step-row-` | one row in the recipe book list | 11 |
| `step-card-` | step title card, detail view | 11 |
| `step-instructions-` | step instruction body, detail view | 11 |
| `overlay-screen-` | full-frame tutorial overlay (scrim + glyph) | 8 |
| `gesture-` | tutorial glyph alone, trimmed, no scrim | 8 |
| `ingredient-` | raw ingredient sprite | 17 |
| `utensil-` | tool sprite | 15 |
| `prepared-` | step-output sprite (bowls, dough, cake) | 12 |
| `ui-` | native-style interface element | 1 |
| **Total** | | **158** |

Screen mockups in `Screens/` keep their own `screen-NN-` prefix (91 files).

---

## `Assets-By-Screen/`

Screen folders are numbered in game-flow order, matching `Screens/`. An asset
lives in a screen folder when **only that screen uses it**; anything used on
three or more screens lives in `_shared/` so there is exactly one copy of it.

### `_shared/` — 61

| Folder | Files | Notes |
|---|---|---|
| `backgrounds/` | 4 | `bg-woods-clearing` (flow screens) and `bg-kitchen-clearing` (09, 11), each with a `-dim` variant used behind modals and tutorials |
| `panels/` | 3 | `panel-stone-slab-plain` · `-vine-1` · `-vine-3` — the mossy slab behind all flow UI. Vine count is decorative; pick by how much width you need to fill |
| `hud/` | 3 | `hud-timer-clock` (empty face — draw the time on top) · `btn-back` · `btn-signpost-next` |
| `characters/` | 7 | bear · beaver · flamingo · fox · rabbit · raccoon · squirrel. Flamingo is the mascot / order giver, the other six are playable |
| `paws/` | 6 | one pair per playable character, empty-handed |
| `sprites/ingredients/` | 14 | six ingredients × light + `-in-use` dark variant, plus `ingredient-strawberry-punnet` and `ingredient-butter-unwrapped` |
| `sprites/utensils/` | 15 | seven tools × light + `-in-use`, plus `utensil-cake-stand` |
| `sprites/prepared/` | 8 | step outputs — bowls, dough, cake base, `prepared-cake-creamed` |
| `ui/` | 1 | `ui-join-kitchen-alert` — native "Join [Name]'s Kitchen?" dialog |

Per the design notes, the dark `-in-use` variants are *"placeholders for when an
ingredient/utensil is being used."*

### Screen folders — 68

| Folder | Files | Contents |
|---|---|---|
| `04-active-kitchens/` | 1 | `btn-signpost-join` |
| `07-recipe/` | 14 | `book-recipe-open` · `book-title-strawberry-shortcake` · `header-todays-order` · `step-rows/` (11) |
| `09-kitchen/` | 9 | `btn-recipe-book` · `map-props/` (8) |
| `10-storage-room/` | 2 | `bg-storage-cupboard` · `prop-storage-rack` |
| `11-stations/` | 20 | `btn-help` · `props/` (3) · `overlays-fullscreen/` (8) · `gesture-glyphs/` (8) |
| `12-recipe-step-details/` | 22 | `step-cards/` (11) · `step-instructions/` (11) |

Screens 01, 02, 03, 05, 06, 08, 13 and 14 have no exclusive assets — they are
built entirely from `_shared/` plus chrome that still needs exporting
(see `MISSING-ASSETS.md`).

---

## `Screens/` — 91 mockups (3496 × 1608)

Design reference, not shipped. Numbered in game-flow order, so an alphabetical
sort of the filenames *is* the flow. Asset folders above reuse these numbers.

| Folder | Files | Maps to |
|---|---|---|
| `01-welcome/` | 1 | `Flow/StartScreenView.swift` |
| `02-enter-chef-name/` | 2 | `Flow/KitchenNameView.swift` |
| `03-number-of-players/` | 1 | `Flow/NumberOfPlayersView.swift` |
| `04-active-kitchens/` | 1 | `Flow/JoinKitchenView.swift` |
| `05-waiting-room/` | 4 | `Flow/WaitingRoomView.swift` |
| `06-head-chef-assignment/` | 2 | — |
| `07-recipe/` | 3 | `Game/RecipeBookView.swift` |
| `08-countdown/` | 1 | — |
| `09-kitchen/` | 2 | `Kitchen/KitchenScene.swift` |
| `10-storage-room/` | 3 | `Special_Station/StorageView.swift` |
| `11-stations/` | 57 | `Screens/*Screen.swift` |
| `12-recipe-step-details/` | 11 | `Game/RecipeBook.swift` |
| `13-settings/` | 1 | `Flow/SettingsView.swift` |
| `14-system-states/` | 2 | — |

`11-stations/` has one folder per station. State suffixes run
`tutorial` → `enter` → `start` → `end` → `leave`; where one Figma frame covered
two states the suffix is joined (`enter-start`, `end-leave`), and multiple
variants of the same state are suffixed `-a`, `-b`, `-c`.
⚠️ `sift-flour` is still missing its `enter` and `start` frames.

---

## Recipe steps — canonical slugs

The same eleven slugs are used by `step-row-`, `step-card-`,
`step-instructions-` and the `screen-12-` mockups, so all four sort into the
same order and line up row by row.

| # | Slug | Station folder | Gesture |
|---|---|---|---|
| 01 | `cut-strawberries` | `cut-strawberries` | — |
| 02 | `macerate-strawberries` | `macerate-strawberries` | `gesture-hold` |
| 03 | `sift-flour` | `sift-flour` | `gesture-shake` |
| 04 | `melt-butter` | `melt-butter` | `gesture-blow` |
| 05 | `beat-eggs` | `crack-egg` | `gesture-tilt-twice` |
| 06 | `mix-dough` | `mix-dough` | `gesture-circle-swirl` |
| 07 | `whip-cream` | `whip-cream` | `gesture-circle-swirl` |
| 08 | `preheat-oven` | `preheat-oven` | — |
| 09 | `bake-base` | `bake-base` | — |
| 10 | `assemble-decorate` | `assemble-decorate` | `gesture-upside-down` + `-circle` |
| 11 | `serve-cake` | — | — |

⚠️ **Copy inconsistency in the design, not in the filenames.** Step 5 reads
*"Crack eggs"* in the recipe-book row but *"Beat Eggs"* on the detail card, and
its station folder is `crack-egg`. Filenames use `beat-eggs` throughout for
consistency — worth settling the wording before it reaches production.

---

## Tutorial overlays — two forms of the same eight glyphs

Each gesture ships twice, so you can pick whichever fits the implementation:

- **`11-stations/overlays-fullscreen/`** — 1748 × 804, an 85 %-opaque white
  scrim across the whole frame with the glyph centred. Drop it straight over a
  station screen; no layout work.
- **`11-stations/gesture-glyphs/`** — the same line art, trimmed to its bounding
  box, no scrim. Use when you want to position it yourself or animate it.

Both sets use **the same eight suffixes**, so `gesture-shake` and
`overlay-screen-shake` are guaranteed to be the same artwork — swap one form for
the other by changing the prefix.

Names describe **the gesture, not the step**, because gestures are reused —
`circle-swirl` serves both *mix dough* and *whip cream*, which is exactly why
Figma exported that overlay twice under two step names (the second copy is
quarantined in `_unused/duplicates/`).

| Suffix | Used by | Figma names it replaced |
|---|---|---|
| `tap` | generic | `tap.png` · `tap overlay.png` |
| `hold` | macerate strawberries | `macerate strawberries.png` · `hold overlay.png` — carries the "Hold" label |
| `shake` | sift flour | `shake phone.png` · `sift flour overlay.png` |
| `blow` | melt butter | `melt butter.png` · `melt butter overlay.png` |
| `tilt-twice` | crack / beat eggs | `crack eggs.png` · `crack egg overlay.png` |
| `circle-swirl` | mix dough, whip cream | `round in circles.png` · `mix dough overlay.png` |
| `upside-down` | pipe base (A) | `phone upside down.png` · `pipe base overlay A.png` |
| `upside-down-circle` | pipe base (B) | `phone upside down round and round.png` · `pipe base overlay B.png` |

---

## `_unused/` — 83 files, safe to delete

Nothing here is referenced. Kept only so the sort is reversible.

| Folder | Files | Why it's out |
|---|---|---|
| `half-res-duplicates/` | 20 | The new drop re-shipped ingredients, utensils and prepared items that were **already in the tree at 2× the resolution** — e.g. `egg.png` came in at 240 × 280 against the existing 480 × 560. The @2x set also carries the dark `-in-use` variants this drop lacks, so the @2x set stays and these are quarantined. Suffixed `-1x-DUPLICATE`. |
| `junk/` | 43 | 42 byte-identical ✅ checkmark markers from the Figma board, plus `blank-frame.png`. ⚠️ see note below |
| `design-notes/` | 15 | Figma sticky notes as PNGs; fully transcribed in `DESIGN-NOTES.md` |
| `superseded-crops/` | 3 | Mockup crops (`back-button`, `recipe-title`, `timer-clock`) that carried baked-in white backgrounds. The new drop supplies all three as clean transparent PNGs |
| `duplicates/` | 2 | `preheat oven, start` was byte-identical to `preheat oven, enter`; `whip cream overlay` is byte-identical to `mix dough overlay` |

⚠️ `_unused/junk/blank-frame.png` (3520 × 1632) is a dashed rectangle that
matches the **drop-zone target** on the station screens. It may be a real asset
— check before deleting.

---

## Verification

- **115 in → 115 out.** Every file in `cook or cooked assets/` is accounted for
  by exactly one destination; SHA-256 compared after every copy.
- **129 keepers, 129 unique basenames, zero collisions** — safe for the flat
  `Assets.xcassets` namespace.
- Every asset was **viewed** before being named; nothing was named from its
  Figma label alone.
- Duplicate detection was perceptual (normalised 32 × 32 luma diff), not
  filename-based — that is how the half-resolution re-exports were caught.
