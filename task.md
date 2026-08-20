# task.md — backlog

One task per loop. Top of `## Now` = next up. See `steps.md` for the cycle.
Convert vague ideas into concrete, verifiable tasks before starting.

## Now

- [ ] **2-device test: mixing-station loop** — `agung/mixing-station` (pushed).
      Verify on two phones: storage → hold prep locks hand → drop at station →
      make raw dough (mixer) → un-deposit → one-per-game → serve → end result +
      stars → back to start. Report what breaks.
- [ ] **Open PR `agung/mixing-station` → main** — only after the 2-device test
      passes. Reviewed merge, not a direct push. Flag the shared-file edits
      (Recipe, KitchenScene, KitchenSession, NetProtocol, WaitingRoomView) in
      the PR description.

## Later

- [ ] **Real art for placeholders** — swap emoji utensil icons in
      `StationPopupView.utensilEmoji` and the 🍽️ animation slot in
      `ResultPopupView` for real assets.
- [ ] **End-game double-overlay** — SpriteKit `KitchenScene.presentEnd()` may
      draw its own end screen on top of the SwiftUI `EndGameResultsView`. Pick
      one (keep SwiftUI). Needs Keira coordination — she owns KitchenScene.
- [ ] **Dedup `EndGameResults.swift`** — exists on both `agung/mixing-station`
      and `agung/end-game-results`. Reconcile when they converge to main.
- [ ] **Networked ingredient rot** — rotten state is decided locally in storage;
      confirm host-authoritative so all chefs agree an item is rotten.
- [ ] **pbxproj signing churn** — `DEVELOPMENT_TEAM` flips per dev and blocks
      branch ops. Team-agree one signing id or gitignore-strategy the file.

## Done

- [x] mixing-station feature built — mixing station, preps-as-items
      (deposit → produce → carry → deposit → un-deposit), station popup, result
      popup, prep-held hand-lock, one-per-game preps, cracked-egg rename,
      end-game result + back-to-start, scrollable popups, host-completion fix.
      Pushed to `origin/agung/mixing-station` @ 40b30ac.
- [x] Storage gacha (ingredients/utensils, rot chance), networked utensil stock.
- [x] Inventory (hold 1 ingredient + 1 utensil) + on-screen indicator bar.
- [x] Gating logic (GatingBridge: required deposits + utensil per action).
- [x] Start / KitchenName / NumberOfPlayers / WaitingRoom screens (forest art).
- [x] Join via Network.framework + Bonjour; landscape-only; Info.plist keys.
- [x] Head-chef randomizer flow — `agung/head-chef-randomizer` (separate branch).
- [x] End-game result + star scoring — `agung/end-game-results` (separate branch).
