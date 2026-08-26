# Art pipeline — Figma to the kitchen

How a drawing gets from Figma into the game. Works on a free Figma account:
nothing here needs Dev Mode, a paid seat, or a plugin.

```
Figma frame, named exactly like the asset
  → export PNG @2x + @3x
  → drop both files in  Assets-agung/drop/
  → Tools/import-art.sh
  → build, commit Cooked/Assets.xcassets
```

The importer creates the `.imageset` / `.spriteatlas` folders and their
`Contents.json` for you. Re-running it is safe — it rebuilds the JSON from
whichever scales are present, so adding a missing `@2x` later just works.

## Naming

**Name the Figma frame exactly the asset name.** Figma uses the layer name as
the filename, which is the whole trick — it is what stops the folder filling up
with `Group 20.png`. The importer routes on the prefix:

| Prefix | Lands in | Seen by |
|---|---|---|
| `station-` `floor-` `wall-` `prop-` `shadow-` | `Kitchen.spriteatlas` | SpriteKit only |
| `chef-` | `Chefs.spriteatlas` | SpriteKit only |
| `food-` `utensil-` `ui-` | catalog root, plain imageset | SwiftUI **and** SpriteKit |

That split is not cosmetic. **SwiftUI's `Image` and `UIImage(named:)` cannot see
inside a sprite atlas** — only `SKTexture` can. Food and utensils show up in the
inventory bar, storage, and the result popup, so they must stay out of the
atlases. Stations and chefs only ever exist inside the scene, so they go in an
atlas and get their draw calls batched.

Names come from identifiers the rules already own (`StationID.rawValue`, a
`CookAction.output`, `UtensilID.rawValue`), so raw values are kept **verbatim,
camelCase and all** — `station-ovenServe-idle`, not `station-oven-serve-idle`.
That is deliberate: it means `KitchenArt` can build every name by string
interpolation and there is no second list to drift.

## The full list

64 drawings. Nothing needs all of them to ship — anything missing keeps its
placeholder shape, so draw in whatever order you like.

**Stations** — `station-<id>-idle` and `-busy` for all ten:

```
chopping  bowl1  bowl2  mixing  table  stove  ovenServe  storage  trash  drawer
```

plus `station-<id>-output` for the seven that can hold a finished prep
(`chopping bowl1 bowl2 mixing table stove ovenServe`). `-output` is the
"something is sitting here, come take it" look — it is what blocks the station.

**Food** — `food-<id>`:

```
strawberries  cream  butter  egg  flour  sugar
choppedStrawberries  maceratedStrawberries  siftedFlour  meltedButter
crackedEgg  rawDough  whippedCream  bakedBase  assembledCake  finishedCake
```

plus `food-<id>-rotten` for the six raw ones, which are the only things storage
can hand you spoiled.

**Utensils** — `utensil-knife` `utensil-sifter` `utensil-whisk` `utensil-mixer`
`utensil-pan`.

**Chefs** — `chef-idle-down` `chef-idle-up` `chef-idle-side`, the same three as
`chef-walk-`, and `chef-busy`. There is no `-left`: the scene draws `side` with
`xScale = -1`. Draw the chef **greyscale** — it gets tinted per player at
runtime, so one body covers all four.

**World** — `floor-tile` (tileable), `wall-back`, `shadow-round`.

## Sizes

The scene runs `scaleMode = .resizeFill`, so one SpriteKit point is one screen
point and layout is computed from `unitPosition × sceneSize`. Art does not need
to match a fixed screen composition — each piece just needs the right size.

| Asset | Points | @2x | @3x |
|---|---|---|---|
| Station | 96 × 58 footprint | 192 × 116 | 288 × 174 |
| Chef | 40 tall | 80 | 120 |
| Food / utensil icon | 40 × 40 | 80 × 80 | 120 × 120 |
| Floor tile | 64 × 64 | 128 × 128 | 192 × 192 |

96 × 58 is `KitchenScene.stationSize` — the footprint the rules use for tap
targets. A station drawing may be **taller** than that (a hood over the stove, a
shelf above the counter): width is matched to the footprint, height follows your
drawing's aspect ratio, and the anchor sits on the bottom edge so the extra
height grows up the back wall instead of covering floor the chefs walk on.

Landscape iPhones range from 667 × 375 pt to 932 × 430 pt, so leave nothing
load-bearing in the outer 30 pt of a full-bleed background.

## Figma export settings

Select the frame → Export panel → add **two** settings:

| Format | Scale | Suffix |
|---|---|---|
| PNG | 2x | `@2x` |
| PNG | 3x | `@3x` |

Figma appends the suffix, giving `station-stove-idle@2x.png` — exactly what the
importer expects. A file with no suffix is filed as `@3x` with a warning.

Make the **frame bounds equal the sprite bounds**. Figma exports the frame, so
stray padding becomes transparent pixels that shift the sprite off its anchor.

## Then run

```bash
Tools/import-art.sh --dry-run   # check the routing first
Tools/import-art.sh
```

## Using it from code

`Cooked/Art/KitchenArt.swift` builds every name and loads it:

```swift
KitchenArt.station(.stove, .busy)          // "station-stove-busy"
KitchenArt.food("siftedFlour")             // "food-siftedFlour"
KitchenArt.texture(name)                   // nil while the art is missing
KitchenArt.stationNode(.stove, footprint: CGSize(width: 96, height: 58))
```

`texture(_:)` returning nil is the load-bearing part: it lets every call site
fall back to the placeholder shape it draws today, so the game stays playable
through the whole art pass instead of going dark the moment one name is wrong.

## Two things that must land before the art does

Both are in files this branch deliberately does not touch — they belong to
teammates and need a word first.

1. **`KitchenScene` still builds stations and chefs from `SKShapeNode`**
   (`KitchenScene.swift:276`, `:85`). Each needs one `if let` in front of it:
   use `KitchenArt.stationNode(...)` when it returns a node, else the shape.
   Keira's file.

2. **`ChefSnapshot` carries no facing and no held item** — just
   `playerID, x, y, station, isBusy`. Neither can be derived on the receiving
   end, and `PlayerInventory` is local per device, so remote chefs' hands are
   invisible. The moment a chef sprite faces a direction or holds a strawberry,
   both fields have to ride the snapshot. Brio's file. Cheap now, painful during
   the art pass.
