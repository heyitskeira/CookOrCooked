# Netcode spec — Networked Storage + Multi-ingredient Deposit

For Brio. These two features are **shared game state**, so they must be
**host-authoritative** like everything else in `KitchenSession`: the host owns
the truth, guests send intent and render the next snapshot. Building them
locally would desync across devices — that's why they're specced here rather
than wired into the scene.

The local models already exist and are the pieces to lift into the snapshot:

- **Utensil stock** → `StoragePantry` (in `StorageStation.swift`). Already has a
  `Snapshot { utensilStock: [String: Int] }` wire shape + `apply(_:)`.
- **Deposit accumulator** → `GatingLogic.swift` (`Station.deposited`,
  `GatingEngine.deposit/availableAction/perform`). A complete, tested (18/18)
  local engine, keyed by its own `FoodID`/`StationType` — map to `StationID`.

---

## 1. Networked storage (limited utensils)

**Why:** some utensils have finite stock (1 knife, 1 mixer, …). Two chefs can't
both hold the only knife.

**State to add to the host snapshot:**
```
utensilStock: [String: Int]     // utensilID -> count remaining
```

**Flow:**
1. Guest opens storage, taps a utensil → sends `RequestUtensil(utensilID)`.
2. **Host** checks `utensilStock[id] > 0`:
   - yes → decrement, (return the guest's previous tool +1), broadcast new stock,
     reply `GrantUtensil(id)`.
   - no → reply `UtensilOut(id)`.
3. Guest applies: on grant, `inventory.pickUp(...)`; on out, show the
   "No X left" popup (already built).

**Messages (add to `NetProtocol`):**
```
case requestUtensil(id: String)          // guest -> host
case grantUtensil(id: String)            // host -> guest
case utensilOut(id: String)              // host -> guest
// stock rides in the periodic snapshot, no separate message needed
```

**Client change:** `StorageView`'s utensil tap currently calls
`pantry.take(...)` locally — swap that for `session.requestUtensil(id)` and let
the grant/out reply drive the result. Ingredients (unlimited, rot rolled) can
stay a local draw, OR move the roll host-side if you want identical RNG for all.

---

## 2. Networked multi-ingredient deposit

**Why:** actions like dough need 5 ingredients; a chef holds 1. Chefs deposit
into a bowl over multiple trips; the action fires when the full set is present.
All players must see the same bowl contents.

**State to add per station in the snapshot:**
```
deposited: [String: [String]]   // stationID -> [foodID] accumulated
```

**Flow:**
1. Guest arrives at a station holding an ingredient → sends
   `Deposit(station, foodID)`.
2. **Host** validates (is it a valid input for a station action? not already
   there?) via the `GatingLogic` engine, appends to `deposited[station]`,
   broadcasts.
3. When `deposited[station]` == an action's required set **and** the acting chef
   holds the right utensil (checked locally, inventory is local) **and** the
   action's `requires` chain is satisfied → the action unlocks. Performing it
   (host-side) clears `deposited[station]` and marks the action done.

**Messages:**
```
case deposit(station: String, foodID: String)   // guest -> host
// deposited state rides in the snapshot
```

**Recipe model gap (Keira):** their `CookAction` has no ingredient list. Add the
required ingredients per action (a field on `CookAction`, or a side table).
`GatingLogic.Recipes` already encodes the exact sets — reuse those.

**Consumption + intermediates:** decide whether a produced item (chopped
strawberries, dough) becomes a **carryable item** deposited onward, or stays an
action-completion flag as today. The full deposit loop wants carryable items;
that's the bigger model change.

---

## What's already done on `develop` (local, ready to network)

- `StoragePantry` — counts, take/give-back, `Snapshot`/`apply`. Wired into
  `StorageView` (shows "N left", out-of-stock popup, returns swapped tools).
- `GatingLogic` — the deposit engine + rules, tested.
- `GatingBridge` — utensil gate already runs before a station opens.
- Inventory stays **local per device** (agreed — host doesn't validate hands).

## Seam summary

Host owns: `utensilStock`, per-station `deposited`, action completion.
Guest owns: its own `PlayerInventory` (local).
Bridge: guest sends `requestUtensil` / `deposit`; host validates with
`GatingLogic` and broadcasts; guests render the snapshot.
