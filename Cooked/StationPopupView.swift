//
//  StationPopupView.swift
//  Cooked
//
//  The choice a chef gets on reaching a station: drop / pick up preps, or do an
//  action. The action button is contextual (a bowl offers several) and dims
//  when it can't be done — wrong utensil, missing deposits, or a leftover prep
//  blocking the station.
//
//  Presentation only: reads the session snapshot + the local inventory, calls
//  `session` for deposits/pick-ups and `onDoAction` to launch the minigame.
//

import SwiftUI

struct StationPopupView: View {
    let station: StationID
    @ObservedObject var session: KitchenSession
    @ObservedObject var inventory: PlayerInventory
    /// Launch the minigame for this action (handled by the scene).
    var onDoAction: (CookAction) -> Void
    var onClose: () -> Void

    @State private var alert: String?

    // MARK: Snapshot-derived state

    private var completed: Set<Int> { Set(session.snapshot.completed) }
    private var deposited: Set<String> { Set(session.snapshot.depositedFoods(at: station)) }
    private var output: String? { session.snapshot.outputFood(at: station) }

    /// Actions this station offers (bowls share). Repeatable producing actions
    /// always appear so preps can be re-made; the one-shot goals (pre-heat,
    /// serve) drop off once done. Trash/rotten is handled by its own flow.
    private var candidates: [CookAction] {
        Recipe.actions.filter { a in
            a.id != 13
            && GameState.sharesActions(station, a.station)
            && (a.isRepeatable || !completed.contains(a.id))
        }
    }

    private func canDo(_ action: CookAction) -> Bool {
        guard output == nil else { return false }                      // blocked by leftover prep
        guard GatingBridge.requiredIngredients(for: action).isSubset(of: deposited) else { return false }
        if let need = GatingBridge.requiredUtensil(for: action) {
            return inventory.utensil?.id == need.rawValue
        }
        return true
    }

    /// The held item can be set down here. Any station takes it (as long as it
    /// isn't blocked by a finished prep and doesn't already hold this item), so
    /// a chef is never stuck carrying something with nowhere to put it.
    private var depositable: HeldIngredient? {
        guard output == nil, let ing = inventory.ingredient, !deposited.contains(ing.id) else { return nil }
        return ing
    }

    // MARK: Body

    var body: some View {
        ZStack {
            Color.black.opacity(0.45).ignoresSafeArea()
                .onTapGesture { onClose() }

            ScrollView {
              VStack(spacing: 16) {
                Text(station.displayName)
                    .font(.system(size: 26, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)

                // ---- Preps: pick up what's finished, or drop what you carry ----
                if let output {
                    prepButton(title: "Pick up \(GatingBridge.displayName(output))", icon: "hand.raised.fill") {
                        if inventory.isHoldingPrep {
                            alert = "You already held on to a prep!"
                            return
                        }
                        if let food = session.pickUpOutput(at: station) {
                            inventory.pickUp(HeldIngredient(id: food, name: GatingBridge.displayName(food), isPrep: true))
                        }
                        onClose()
                    }
                }
                if let drop = depositable {
                    prepButton(title: "Drop \(drop.name)", icon: "tray.and.arrow.down.fill") {
                        session.deposit(drop.id, at: station)
                        inventory.dropIngredient()
                        // Stay open: the snapshot updates and the action button
                        // lights up on its own — no need to re-tap the station.
                    }
                }

                // ---- Actions (contextual; dimmed when they can't run) ----
                ForEach(candidates, id: \.id) { action in
                    actionButton(action)
                }

                // Only truly empty — no action, nothing to pick up, nothing to drop.
                if candidates.isEmpty && output == nil && depositable == nil {
                    Text("Nothing to do here right now")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppTheme.ink.opacity(0.5))
                }

                Button("Close", action: onClose)
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.6))
                    .padding(.top, 4)
              }
              .padding(32)
            }
            .frame(maxWidth: 460, maxHeight: 360)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous).fill(AppTheme.cream)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous).stroke(AppTheme.ink, lineWidth: 4)
            )
            .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            .padding(40)

            if let alert {
                PrepHeldAlert(message: alert) { self.alert = nil }
            }
        }
    }

    private func actionButton(_ action: CookAction) -> some View {
        let enabled = canDo(action)
        return Button {
            onDoAction(action)
            onClose()
        } label: {
            HStack(spacing: 12) {
                if let u = GatingBridge.requiredUtensil(for: action) {
                    Text(utensilEmoji(u))
                }
                Text(action.name)
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(AppTheme.cream)
            .padding(.horizontal, 20)
            .frame(height: 60)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(AppTheme.tomato))
            .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 3))
        }
        .buttonStyle(.plain)
        .opacity(enabled ? 1 : 0.4)
        .disabled(!enabled)
    }

    private func prepButton(title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                Text(title).font(.system(size: 18, weight: .bold, design: .rounded))
                Spacer()
            }
            .foregroundStyle(AppTheme.ink)
            .padding(.horizontal, 20)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background(Capsule().fill(.white))
            .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 2.5))
        }
        .buttonStyle(.plain)
    }

    private func utensilEmoji(_ u: UtensilID) -> String {
        switch u {
        case .knife:  return "🔪"
        case .sifter: return "🫓"
        case .whisk:  return "🥄"
        case .mixer:  return "🌀"
        case .pan:    return "🍳"
        }
    }
}

/// Small centered alert used when a chef tries to take something while already
/// holding a prep. Shared by the station, result, and storage screens.
struct PrepHeldAlert: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.5).ignoresSafeArea()
                .onTapGesture { onDismiss() }
            VStack(spacing: 16) {
                Text("🙌").font(.system(size: 44))
                Text(message)
                    .font(.system(size: 20, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .multilineTextAlignment(.center)
                Button("OK", action: onDismiss)
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.cream)
                    .frame(width: 140, height: 52)
                    .background(Capsule().fill(AppTheme.tomato))
                    .overlay(Capsule().stroke(AppTheme.ink, lineWidth: 3))
            }
            .padding(32)
            .background(RoundedRectangle(cornerRadius: 24, style: .continuous).fill(AppTheme.cream))
            .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(AppTheme.ink, lineWidth: 4))
            .padding(50)
        }
    }
}
