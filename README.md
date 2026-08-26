# Cook or Cooked

A local co-op cooking game for iPhone. 2–4 players connect over the same
Wi-Fi, split up around a shared kitchen, and race the clock to finish a
Strawberry Shortcake — together. One chef reads the recipe; everyone else
has to listen.

Win if the cake is served before time runs out. Lose if it isn't.

## At a glance

- **Platform:** iOS, iPhone only, portrait, top-down 2D
- **Players:** 2–4, local co-op over the same Wi-Fi network (no internet
  connection required, no backend server)
- **Built with:** SpriteKit (the kitchen) + SwiftUI (every screen around it),
  Xcode only — no third-party engine or package dependencies
- **Networking:** Bonjour + `Network.framework`, host-authoritative

## Requirements

- Xcode 26.6 or newer
- iOS 26.5+ deployment target
- Two physical iPhones to test multiplayer for real. Local networking
  between two iOS Simulators is unreliable — Bonjour discovery in particular
  tends not to work simulator-to-simulator.

## Running it

1. Open `Cooked.xcodeproj`.
2. Build and run the `Cooked` scheme.
3. On first launch on a real device, allow the local network permission
   prompt — without it, hosting and joining both fail silently.

To actually play, you need two devices on the same Wi-Fi: one hosts a
kitchen, the other joins with the room code the host shows. Single-device
testing is possible for most of the game (drop the `session` argument and
things fall back to an offline path — see `KitchenScene.session`), but the
lobby, serving ritual, and anything host/guest-specific need two devices to
be meaningful.

## How a match works

The kitchen has nine stations (`StationID.mapStations` in `Game/Recipe.swift`)
ringing a forest clearing, with the serve stone in the middle. Their positions
are measured off the reference art rather than chosen by hand — the stone pads
the props stand on are painted into `bg-kitchen-clearing`, so a station cannot
be moved without moving its pad too.

`StationID` itself still has ten cases. The tenth, `drawer`, is not on the map:
its shelves are the Storage Rack tab inside the pantry. The case stays because
it is the key those shelves travel under in `GameSnapshot` and `RoomResume`.

Chefs walk up to a station, and a SwiftUI popup (`StationPopupView`) offers whatever action is
possible there — dropping off an ingredient, picking up a finished prep, or
doing an action if the right ingredients are deposited and the right utensil
is in hand.

Doing an action opens a full-screen minigame (chopping, whisking, sifting,
melting, mixing, cracking an egg — see `Screens/`) that fills the chef's
hands with the resulting prep once finished.

Serving is deliberately not something one chef can do alone: the whole
connected team has to walk back to the middle of the room and hold a button
together (`Kitchen/ServeRitual.swift`). That's the moment the match can be
won or lost.

## Project structure

```
Cooked/
  App/          Entry point (CookedApp, the UIKit fallback controller)
  Flow/         Screens between launch and the kitchen — start, kitchen
                name/join, waiting room, settings, end-of-game results
  Game/         The recipe itself: stations, actions, GameState, the recipe
                book UI, and the two gating rule engines
  Networking/   Everything that crosses the wire — wire protocol, transport
                (Bonjour), and KitchenSession (the host-authoritative lobby
                + game sync)
  Kitchen/      The live SpriteKit scene and its SwiftUI chrome — the map,
                the serve ritual, station popups, result popups
  Inventory/    A chef's two hands (one ingredient slot, one utensil slot)
                and the UI that shows them
  Audio/        Music and sound effects
  Screens/      The full-screen minigames each action opens, plus the
                storage room — utensils, ingredients and the storage
                rack (cold/room-temp shelves), as three tabs
  Dev/          A manual test menu for opening individual screens in
                isolation — not part of the real player-facing flow
  Theme.swift   Shared colours, fonts, and button styles
```

Xcode's project navigator mirrors this folder structure automatically
(synchronized groups) — move a file on disk and it moves in Xcode too, no
`.pbxproj` surgery required. `Info.plist` is the one exception: its path is
hardcoded in the build settings, so it has to stay at `Cooked/Info.plist`.

## Architecture notes

**Host-authoritative networking.** One device is the host; it owns the only
real `GameState`. Guests never mutate shared state directly — they send
intent (`moveTo`, `claimStation`, `deposit`, …) and render whatever the
host's next snapshot says, broadcast about ten times a second. This is what
keeps up to four devices agreeing without any conflict-resolution logic.
See the doc comment at the top of `Networking/KitchenSession.swift`.

**Two rule systems, one recipe.** `Game/Recipe.swift` defines the 13 actions
players actually perform (via `requires: [Int]`, an ordering-only gate).
`Game/GatingLogic.swift` is a separate, self-contained engine built around
ingredients, utensils, and station state (`FoodID`, `UtensilID`,
`GatingEngine`). `Game/GatingBridge.swift` is the seam between them. These
two haven't fully merged yet — see the comments in those three files before
changing either one, so a recipe edit doesn't only take effect in half the
game.

**Joining is gated twice.** A room code proves a guest can see the host's
screen. On supported hardware, a brief ultra-wideband ranging check
(`Networking/ProximityGate.swift`) adds a same-room distance check on top —
and fails open if the hardware or permission isn't there, so it's a bonus,
never the only gate.

## Known rough edges

- `Screens/Special_Station/ChooseAction.swift` predates `StationPopupView`
  and isn't wired into the live game — it references a station/recipe model
  (`StationType`, `GatingRecipe`) that nothing else in the running app reads.
- `Dev/ContentView.swift` and `App/GameViewController.swift` aren't part of
  the real launch path (`CookedApp` opens `StartScreenView` directly) — they
  exist for trying individual screens without playing a full match.
- `Docs/NetworkingSpec-Storage-Deposit.md` is an implementation spec for
  networked storage/deposit that has since been built — kept for the
  reasoning behind the design, not as a to-do list.

## Contributing

Branches follow `<name>/<short-description>` (e.g. `agung/fix-kitchen-loop`,
`brio/fix-serve-logic-bug`); PRs merge into `main`. If you're touching
`NetProtocol.swift` or `GameSnapshot`, that's a wire-format change — flag it
to whoever else is working on networking, since guest and host both need to
agree on the shape.
