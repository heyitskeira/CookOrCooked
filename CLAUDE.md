# Cook or Cooked — project context

Co-op iPhone game: 2–4 chefs on the same Wi-Fi race to bake a Strawberry
Shortcake before a timer. Landscape, iPhone-only. Local multiplayer (no server).

## Build / run

```bash
xcodebuild -scheme Cooked -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' build
```

- Deployment target **iOS 26.5** — the simulator must have the iOS 26.5 runtime
  (an older sim errors "Requires a Newer Version of iOS").
- **Multiplayer needs two real devices** — Bonjour + UWB don't work sim-to-sim.
  Solo testing reaches the kitchen only via the `ContentView` test menu
  ("Kitchen map"), not the real Start → lobby flow (the lobby needs 2 players).
- To eyeball a single SwiftUI screen: temporarily point `CookedApp`'s root at it,
  `xcrun simctl` install + launch + screenshot, then **revert the root**.

## Architecture

Two rendering layers: **SwiftUI** for screens/overlays, **SpriteKit** for the
kitchen map + station minigames. `KitchenGameView` hosts the `SpriteView` and
stacks the SwiftUI overlays (inventory bar, storage, station popup, result,
end-game) on top in a `ZStack`.

**Multiplayer is host-authoritative.** The host owns the only real `GameState`;
it broadcasts a `GameSnapshot` ~10×/sec. Guests send *intent* and render whatever
the snapshot says. Never mutate shared state on a guest.

- `KitchenSession.swift` — the session (host + guest). Owns roster, phases,
  and (host) the authoritative tables. Applies completions via `applyCompletion`.
- `NetProtocol.swift` — all wire types (`nonisolated`): `NetMessage`,
  `GameSnapshot`, `Player`, `ChefSnapshot`. **Snapshot fields:** `completed`,
  `mess`, `timeRemaining`, `chefs`, `occupancy` (station locks), `utensilStock`,
  `deposited` (per-station ingredients), `stationOutput` (finished prep on a
  station, blocks it until taken).
- `KitchenTransport.swift` / `BonjourTransport` — Network.framework + Bonjour.
- `ProximityGate.swift` — UWB "are you in the room" check at join time only.
- `Recipe.swift` — `StationID`, `CookAction` (`station`, `motion`, `requires`,
  `output`, `isRepeatable`), `Recipe.actions`, `GameState` (win = all one-shot
  goals completed).

### The cooking loop (current model)

Preps are **carryable items**, not flags:

```
storage (gacha, rot chance) → hold 1 ingredient + 1 utensil (a held PREP locks the hand)
 → walk to a station → STATION POPUP: drop / pick-up / do-action (contextual, dimmed if not ready)
 → minigame → produces a PREP onto the station (stationOutput, blocks it) → RESULT POPUP: hands / station
 → carry prep → next station → drop → … → dough → bake → assemble → serve (win) → END-GAME result + stars
```

- Order is enforced by **deposits**, not `requires` (which survives only for the
  oven pre-heat gate). Each producing action is **one-per-game**.
- `GatingBridge.swift` maps `CookAction` → required deposits + required utensil,
  and holds food display names / raw-vs-prep. It's the seam between the team's
  `CookAction` model and this project's inventory rules.
- `PlayerInventory` is **local per device** (host doesn't validate hands).
  `StoragePantry` utensil stock is networked (host-owned, in the snapshot).

### Key SwiftUI files

`StartScreenView` (art) → `KitchenNameView` → `NumberOfPlayersView` (creates host
session) → `WaitingRoomView` → head-chef flow (on some branches) → `KitchenGameView`.
Overlays: `StorageView`, `StationPopupView`, `ResultPopupView`, `EndGameResultsView`,
`InventoryBar`. Shared style in `Theme.swift` (`AppTheme`). `.returnToStart`
notification collapses the whole cover stack back to Start.

## Conventions

- **One feature per branch** (`agung/<feature>`). Merge to `main` via a reviewed
  **PR**, never a direct push. `develop` is the integration branch.
- **Shared files are owned by teammates** — `Recipe.swift`, `KitchenScene.swift`,
  `KitchenSession.swift`, `NetProtocol.swift` are Keira's (stations/scene/recipe)
  and Brio's (netcode/queue). **Coordinate before editing them.**
- **Build green before every commit.** Verify UI on device when it matters.
- Don't push mid-feature. Commit messages end with the Co-Authored-By trailer.
- New netcode follows the existing pattern: guest sends intent → host mutates a
  table → it rides the next snapshot (or a direct reply). Add wire types to
  `NetProtocol` as `nonisolated`.

## Gotchas

- **`project.pbxproj` `DEVELOPMENT_TEAM`** flips to each dev's personal signing id
  and blocks branch switches — discard it (`git checkout -- Cooked.xcodeproj/project.pbxproj`).
- **`xcuserstate`** is gitignored; discard local changes to it before merges.
- `Info.plist` must keep `NSBonjourServices` (`_cookorcooked._tcp`),
  `NSLocalNetworkUsageDescription`, `NSNearbyInteractionUsageDescription`.
- iPhone orientations are **landscape-only**.

## Team / repo

Repo `heyitskeira/CookOrCooked`. Agung (UI + storage/inventory/gating/mixing,
still learning git), Keira (stations/scene/recipe), Brio (multiplayer/queue).
