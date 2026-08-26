# Missing Assets — UI visible in `Screens/` but absent from the asset tree

Audited 2026-08-26 against the sprite set (34), `UI/` (1), and
`Cooked/Assets.xcassets` (13 imagesets). Revised after an element-level pass over
`07-recipe/` and `12-recipe-step-details/` (+11 assets, section F rewritten).

---

## ⚡ Status after the `cook or cooked assets` drop (2026-08-26)

**The drop closed 31 of the 65 gaps. 26 remain fully open; 8 arrived partially.**
The sections below are the *original* audit and have not been rewritten — use
this table as the overlay.

### ✅ Closed — 31

| Was missing | Now at |
|---|---|
| `bg-forest-flow` | `_shared/backgrounds/bg-woods-clearing` |
| `bg-forest-station` | `_shared/backgrounds/bg-woods-clearing-dim` |
| `bg-kitchen-clearing` | `_shared/backgrounds/bg-kitchen-clearing` (+ `-dim`) |
| `bg-cabinet-interior` | `10-storage-room/bg-storage-cupboard` |
| `bg-storage-rack` | `10-storage-room/prop-storage-rack` |
| `mossy-rock-panel` | `_shared/panels/panel-stone-slab-plain` (+ 2 vine variants) |
| `timer-alarm-clock` | `_shared/hud/hud-timer-clock` — empty face, draw the time on top |
| `signpost-arrow` | `_shared/hud/btn-signpost-next` + `04-active-kitchens/btn-signpost-join` |
| `help-button` | `11-stations/btn-help` |
| `recipe-book-button` | `09-kitchen/btn-recipe-book` |
| `banner-todays-order` | `07-recipe/header-todays-order` |
| `recipe-book-open` | `07-recipe/book-recipe-open` |
| `recipe-book-empty-pages` | `07-recipe/book-recipe-open` — it ships empty |
| `recipe-title-wordmark` | `07-recipe/book-title-strawberry-shortcake` |
| `recipe-row-pill` | `07-recipe/step-rows/` — all 11, badge baked in |
| `recipe-step-icons` | `07-recipe/step-rows/` — all 11 badges |
| `recipe-step-icons-07-11` | `07-recipe/step-rows/` |
| `recipe-step-title-card` | `12-recipe-step-details/step-cards/` — all 11 |
| `hint-tap-hand` | `11-stations/gesture-glyphs/gesture-tap` |
| `char-flamingo` `char-fox` `char-rabbit` `char-raccoon` `char-squirrel` | `_shared/characters/` (bear + beaver came too — 7 total) |
| `paw-hands` | `_shared/paws/` — one pair per playable character |
| `prop-oven-dome` | `11-stations/props/prop-oven-closed` + `prop-oven-open` |
| `prop-stove` | `11-stations/props/prop-stove-top` |
| `prop-storage-cabinet` | `09-kitchen/map-props/station-storage` |
| `prop-trash-can` | `09-kitchen/map-props/station-trash` |
| `prop-mixing-table` | `09-kitchen/map-props/station-mixing` |
| `prop-cake-stand` | `_shared/sprites/utensils/utensil-cake-stand` |

**Bonus, not on the original list:** 8 full-frame tutorial overlays + 8 trimmed
gesture glyphs (`11-stations/`), 11 step instruction bodies
(`12-recipe-step-details/step-instructions/`), `ingredient-butter-unwrapped`
and `prepared-cake-creamed`.

### ⚠️ Partial — 8 (art arrived, but not as a separate asset)

| Asset | What arrived | What's still needed |
|---|---|---|
| `station-label-plaque` | plaque is **attached** to each `09-kitchen/map-props/station-*` | standalone plaque, so names can be data-driven |
| `station-name-plaque-left` | same | standalone, left-anchored |
| `station-name-plaque-right` | same | standalone, right-anchored |
| `prop-bowl-empty` | `station-bowl-1` / `station-bowl-2`, plaque attached | plaque-free variant for the station close-up |
| `prop-chopping-board` | `station-chopping`, plaque attached | plaque-free, kitchen-map size |
| `prop-chopping-board-large` | `station-chopping`, plaque attached | plaque-free, station-screen size |
| `ivy-vine-overlay` | vines are **baked into** `panel-stone-slab-vine-1` / `-3` | standalone vine, so it can be layered anywhere |
| `recipe-leaf-decor-set` | foliage is **baked into** each `step-card-*` | the 11 sprites separately, if they need to animate |

### ❌ Still open — 26

`action-button-pair` · `action-button-pill` · `avatar-card-frame` ·
`carousel-arrow-left` · `carousel-arrow-right` · `char-counter-pill` ·
`char-group-all` · `icon-cutlery` · `icon-tip-bulb` · `icon-warning` ·
`kitchen-list-row-default` · `kitchen-list-row-selected` · `name-pill` ·
`paw-hands-holding` · `player-count-buttons` · `plus-operator-glyph` ·
`prop-assembly-bench` · `prop-serve-stone` · `prop-skillet` ·
`settings-slider` · `station-hanging-sign` · `step-number-chip` ·
`step-progress-bar` · `tab-pill-active` · `tab-row` · `text-field`

Almost all of it is **flow-screen interface chrome** — text fields, list rows,
pills, sliders, tabs, arrows. The two art gaps worth flagging: the kitchen map
shows an **ASSEMBLY STATION** bench and a **GATHER HERE TO SERVE** stone that
the drop skipped, and the paws only ship empty-handed even though the station
screens show them **gripping a utensil**.

---

## Original audit — 65 elements

Every row below has a cropped reference image in **`_missing-refs/`**, named after the
target asset. For a visual gallery open **`asset-gaps.html`** in a browser.

> Crops are reference only — they carry baked-in backgrounds. Re-export from Figma as
> transparent PNGs (@2x/@3x) rather than cutting these out.


## A. HUD & controls — 20

| Asset | Appears on screen | Reference crop | Notes |
|---|---|---|---|
| `timer-alarm-clock` | `screen-09-kitchen-head-chef.png` | `_missing-refs/timer-alarm-clock.png` | Brass alarm clock; also on storage + every station |
| `station-hanging-sign` | `screen-11-melt-butter-start.png` | `_missing-refs/station-hanging-sign.png` | Hanging plaque: timer + station name |
| `recipe-book-button` | `screen-09-kitchen-head-chef.png` | `_missing-refs/recipe-book-button.png` | Head chef only, top-left |
| `help-button` | `screen-11-cut-strawberries-start.png` | `_missing-refs/help-button.png` | '?' opens station tutorial |
| `tab-pill-active` | `screen-10-storage-utensils-view-a.png` | `_missing-refs/tab-pill-active.png` | Filled cream pill |
| `tab-row` | `screen-10-storage-utensils-view-a.png` | `_missing-refs/tab-row.png` | All 3 tabs: active + 2 inactive |
| `carousel-arrow-left` | `screen-10-storage-utensils-view-a.png` | `_missing-refs/carousel-arrow-left.png` | White chevron |
| `carousel-arrow-right` | `screen-10-storage-utensils-view-a.png` | `_missing-refs/carousel-arrow-right.png` | White chevron |
| `step-number-chip` | `screen-11-cut-strawberries-start.png` | `_missing-refs/step-number-chip.png` | Red numbered badge |
| `step-progress-bar` | `screen-11-cut-strawberries-start.png` | `_missing-refs/step-progress-bar.png` | Chip + track + label field |
| `action-button-pill` | `screen-11-cut-strawberries-start.png` | `_missing-refs/action-button-pill.png` | 'Start chopping' |
| `action-button-pair` | `screen-11-cut-strawberries-end.png` | `_missing-refs/action-button-pair.png` | 'Pick up' / 'Leave' |
| `settings-slider` | `screen-13-settings.png` | `_missing-refs/settings-slider.png` | Track, knob, - and + glyphs |
| `kitchen-list-row-default` | `screen-04-active-kitchens.png` | `_missing-refs/kitchen-list-row-default.png` | Cream row |
| `kitchen-list-row-selected` | `screen-04-active-kitchens.png` | `_missing-refs/kitchen-list-row-selected.png` | Dark brown row |
| `avatar-card-frame` | `screen-05-waiting-room-host.png` | `_missing-refs/avatar-card-frame.png` | Rounded cream card |
| `name-pill` | `screen-05-waiting-room-host.png` | `_missing-refs/name-pill.png` | Player name under card |
| `text-field` | `screen-02-chef-name-a.png` | `_missing-refs/text-field.png` | Chef name input |
| `char-counter-pill` | `screen-02-chef-name-a.png` | `_missing-refs/char-counter-pill.png` | '12/12' |
| `player-count-buttons` | `screen-03-player-count.png` | `_missing-refs/player-count-buttons.png` | 2/3/4, selected + unselected |

## B. Signage & panels — 5

| Asset | Appears on screen | Reference crop | Notes |
|---|---|---|---|
| `signpost-arrow` | `screen-05-waiting-room-host.png` | `_missing-refs/signpost-arrow.png` | Same shape for NEXT/JOIN/START/RECIPE |
| `banner-todays-order` | `screen-07-recipe-other-chefs.png` | `_missing-refs/banner-todays-order.png` | Wide plank banner hung from two ropes; wider than `station-hanging-sign` |
| `mossy-rock-panel` | `screen-13-settings.png` | `_missing-refs/mossy-rock-panel.png` | Stone slab behind all flow UI |
| `ivy-vine-overlay` | `screen-05-waiting-room-host.png` | `_missing-refs/ivy-vine-overlay.png` | Decorative vine, left edge of rock panel |
| `station-label-plaque` | `screen-09-kitchen-head-chef.png` | `_missing-refs/station-label-plaque.png` | Kitchen map label |

## C. Characters — 8

| Asset | Appears on screen | Reference crop | Notes |
|---|---|---|---|
| `char-flamingo` | `screen-01-welcome.png` | `_missing-refs/char-flamingo.png` | Mascot / order giver |
| `char-group-all` | `screen-01-welcome.png` | `_missing-refs/char-group-all.png` | Bear, rabbit, squirrel, beaver, raccoon, fox |
| `char-squirrel` | `screen-05-waiting-room-host.png` | `_missing-refs/char-squirrel.png` | Avatar, in card |
| `char-raccoon` | `screen-05-waiting-room-host.png` | `_missing-refs/char-raccoon.png` | Avatar, in card |
| `char-rabbit` | `screen-05-waiting-room-host.png` | `_missing-refs/char-rabbit.png` | Avatar, in card |
| `char-fox` | `screen-05-waiting-room-host.png` | `_missing-refs/char-fox.png` | Avatar, in card |
| `paw-hands` | `screen-10-storage-rack-view.png` | `_missing-refs/paw-hands.png` | Player hands; HandsNode.swift needs this |
| `paw-hands-holding` | `screen-11-cut-strawberries-start.png` | `_missing-refs/paw-hands-holding.png` | Hands gripping a utensil |

## D. Kitchen props — 12

| Asset | Appears on screen | Reference crop | Notes |
|---|---|---|---|
| `prop-stove` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-stove.png` | Stone stove, two hobs |
| `prop-oven-dome` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-oven-dome.png` | Stone dome oven |
| `prop-chopping-board` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-chopping-board.png` | Kitchen-map size |
| `prop-chopping-board-large` | `screen-11-cut-strawberries-start.png` | `_missing-refs/prop-chopping-board-large.png` | Station-screen size |
| `prop-mixing-table` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-mixing-table.png` |  |
| `prop-assembly-bench` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-assembly-bench.png` |  |
| `prop-bowl-empty` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-bowl-empty.png` | Bowl station |
| `prop-storage-cabinet` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-storage-cabinet.png` |  |
| `prop-trash-can` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-trash-can.png` | Wooden bucket |
| `prop-serve-stone` | `screen-09-kitchen-head-chef.png` | `_missing-refs/prop-serve-stone.png` | 'GATHER HERE TO SERVE' |
| `prop-skillet` | `screen-11-melt-butter-start.png` | `_missing-refs/prop-skillet.png` | NOT the same art as utensil-saucepan |
| `prop-cake-stand` | `screen-11-assemble-decorate-start-a.png` | `_missing-refs/prop-cake-stand.png` | Pink pedestal |

## E. Backgrounds — 5

| Asset | Appears on screen | Reference crop | Notes |
|---|---|---|---|
| `bg-forest-flow` | `screen-13-settings.png` | `_missing-refs/bg-forest-flow.png` | Bright forest, flow screens |
| `bg-forest-station` | `screen-11-whip-cream-enter.png` | `_missing-refs/bg-forest-station.png` | Darker forest, station screens |
| `bg-kitchen-clearing` | `screen-09-kitchen-head-chef.png` | `_missing-refs/bg-kitchen-clearing.png` | Grass clearing with station slots |
| `bg-storage-rack` | `screen-10-storage-rack-view.png` | `_missing-refs/bg-storage-rack.png` | 3-shelf wooden rack |
| `bg-cabinet-interior` | `screen-10-storage-utensils-view-a.png` | `_missing-refs/bg-cabinet-interior.png` | Drawer interior + iron hinges |

## F. Recipe book — 12

Covers both `Screens/07-recipe/` (3 mockups) and `Screens/12-recipe-step-details/`
(11 mockups). The ingredient / utensil / prepared-item icons shown on the right-hand
page are **already exported** under `Sprites/` — nothing new needed there. Everything
below is book chrome and is still baked into the flattened screens.

| Asset | Appears on screen | Reference crop | Notes |
|---|---|---|---|
| `recipe-book-open` | `screen-07-recipe-head-chef-in-game.png` | `_missing-refs/recipe-book-open.png` | Two-page spread frame, wood binding + ivy |
| `recipe-book-empty-pages` | `screen-07-recipe-other-chefs.png` | `_missing-refs/recipe-book-empty-pages.png` | Dotted-rule waiting state shown to non-head chefs |
| `recipe-title-wordmark` | `screen-07-recipe-head-chef-in-game.png` | `_missing-refs/recipe-title-wordmark.png` | 'STRAWBERRY SHORTCAKE' red drop-cap lettering — art, not a font |
| `recipe-row-pill` | `screen-07-recipe-head-chef-in-game.png` | `_missing-refs/recipe-row-pill.png` | Tappable step row, hairline outline |
| `recipe-step-icons` | `screen-07-recipe-head-chef-in-game.png` | `_missing-refs/recipe-step-icons.png` | Badges **1–6**, left page. Each is a number + its own food thumbnail |
| `recipe-step-icons-07-11` | `screen-07-recipe-head-chef-in-game.png` | `_missing-refs/recipe-step-icons-07-11.png` | Badges **7–11**, right page. 11 distinct badges total, not 6 |
| `recipe-step-title-card` | `screen-12-recipe-step-01-cut-strawberries.png` | `_missing-refs/recipe-step-title-card.png` | Rounded cream panel holding 'STEP n:' + step name |
| `recipe-leaf-decor-set` | all 11 `screen-12-recipe-step-*.png` | `_missing-refs/recipe-leaf-decor-set.png` | **11 different** foliage sprites, one per step — oak, fern, maple, acorn cluster, etc. Contact sheet of all 11 |
| `plus-operator-glyph` | `screen-12-recipe-step-01-cut-strawberries.png` | `_missing-refs/plus-operator-glyph.png` | '+' between required items; up to 3 per screen (step 10) |
| `station-name-plaque-right` | `screen-12-recipe-step-01-cut-strawberries.png` | `_missing-refs/station-name-plaque-right.png` | Ribbon plaque attached to the **right** of the station prop |
| `station-name-plaque-left` | `screen-12-recipe-step-10-assemble-decorate.png` | `_missing-refs/station-name-plaque-left.png` | Same plaque mirrored to the **left**. Export both or one + flip |
| `hint-tap-hand` | `screen-07-recipe-head-chef-in-game.png` | `_missing-refs/hint-tap-hand.png` | Tapping-paw glyph before 'a step for more instructions' |

## G. Status icons — 3

| Asset | Appears on screen | Reference crop | Notes |
|---|---|---|---|
| `icon-warning` | `screen-14-state-station-busy.png` | `_missing-refs/icon-warning.png` | Station busy |
| `icon-cutlery` | `screen-14-state-incorrect-ingredients.png` | `_missing-refs/icon-cutlery.png` | Wrong ingredients/utensils |
| `icon-tip-bulb` | `screen-12-recipe-step-10-assemble-decorate.png` | `_missing-refs/icon-tip-bulb.png` | Lightbulb before 'Ensure that Step n has been completed'; steps 2, 6, 9, 10, 11 |

---

## Already covered — don't re-export

| Asset | Where |
|---|---|
| `back-button` | `Assets.xcassets` |
| `create-kitchen`, `join-kitchen` | `Assets.xcassets` (welcome planks) |
| `kitchen-name` | `Assets.xcassets` — ⚠️ partial, see `text-field` |
| `chefs-amount` | `Assets.xcassets` — ⚠️ partial, see `player-count-buttons` |
| `start-animals` | `Assets.xcassets` — ⚠️ flat group only; waiting room needs each animal separately |
| `woods-clearing-art`, `trunk-planks` | `Assets.xcassets` |
| `settings-button`, `create-button`, `StartLogo`, `blue-bg-dotted`, `setup-your-kitchen` | `Assets.xcassets` |

## Watch out for

- **`prop-skillet` ≠ `utensil-saucepan`.** The stove version is dark metal with a flower
  tied to the handle; the storage-room version is polished steel with a wooden handle.
  Two different assets.
- **`prop-chopping-board` has two sizes** — a small one on the kitchen map and a large
  one filling the station screen. Export both or one at the larger size.
- **`start-animals` is not reusable** for the waiting room. Those cards need six separate
  avatar sprites (`char-squirrel`, `char-raccoon`, `char-rabbit`, `char-fox`, plus bear
  and beaver, which only ever appear in the welcome group shot).
- **`_unused/junk/blank-frame.png`** is the dashed drop-zone target from the station
  screens, not junk. Rescue it before deleting that folder.
- **The recipe step badges are 11 unique sprites, not a reusable number chip.** Each
  carries its own food illustration behind the numeral. Don't plan on compositing a
  generic badge with a digit.
- **`station-name-plaque` ≠ `station-label-plaque`.** The recipe-book plaque is a wide
  ribbon that butts against the station prop; `station-label-plaque` is the small tag
  on the kitchen map.
- **`recipe-leaf-decor-set` is a contact sheet**, not a shippable asset — it exists so
  you can see all 11 foliage variants at once. Export them individually from Figma.

## Suggested export order

1. **HUD & controls** (20) — needed on nearly every screen
2. **Characters** (8) — blocks the waiting room and every station; `HandsNode.swift` already expects the hands
3. **Signage & panels** (5) — blocks the whole pre-game flow
4. **Kitchen props** (12) — blocks the kitchen map
5. **Recipe book** (12) — blocks `RecipeBookView.swift` and `RecipeBook.swift`
6. Backgrounds and status icons (8)
