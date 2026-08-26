//
//  StorageChrome.swift
//  Cooked
//
//  The furniture all three storage tabs wear: the back plaque top-left, the
//  tab pill across the top, the alarm clock top-right, and the chef's paws in
//  the bottom-right corner.
//
//  It sits here rather than in `StationChrome` because the two are measured
//  against different artboards (see `StorageCanvas`) and only the paws are
//  actually the same drawing. Sharing the station versions would mean either
//  converting every number at the call site or moving both artboards into one
//  type — more coupling than three small views are worth.
//

import SwiftUI

// MARK: - Which shelf you're looking at

/// The three shelves of the cupboard, in the order the design shows them:
/// utensils, ingredients, storage rack.
enum StorageTab: String, CaseIterable, Identifiable {
    case utensils, ingredients, rack

    var id: String { rawValue }

    var title: String {
        switch self {
        case .utensils:    return "Utensils"
        case .ingredients: return "Ingredients"
        case .rack:        return "Storage Rack"
        }
    }
}

// MARK: - Palette

/// Matched to the storage art rather than to `AppTheme` (the menu palette).
enum StoragePalette {
    /// The cream of the selected pill and the captions.
    static let cream = Color(red: 0.99, green: 0.95, blue: 0.89)
    /// The dark wood the selected pill's label is cut out of.
    static let ink = Color(red: 0.34, green: 0.20, blue: 0.13)
}

// MARK: - Back plaque

/// The wooden plaque with the cream arrow that leaves the storage room.
struct StorageBackButton: View {

    let geo: GeometryProxy
    var action: () -> Void

    /// The source PNG (104x156 at 2x) is a plank with a post rising above it
    /// for hanging. Only the plank carries the arrow, so this scales to width
    /// and crops to the bottom — the same treatment `StationBackButton` gives
    /// the signpost, for the same reason.
    static let frame = CGRect(x: 41, y: 18, width: 64, height: 64)

    var body: some View {
        Button(action: action) {
            Group {
                if let art = UIImage(named: "ui-back-button") {
                    GeometryReader { box in
                        Image(uiImage: art)
                            .resizable()
                            .frame(width: box.size.width,
                                   height: box.size.width * (156.0 / 104.0))
                            .frame(width: box.size.width, height: box.size.height,
                                   alignment: .bottom)
                            .clipped()
                    }
                } else {
                    Image(systemName: "arrowshape.turn.up.backward.fill")
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(StoragePalette.cream)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Leave storage")
        .storagePlaced(Self.frame, in: geo)
    }
}

// MARK: - Tab pill

/// Utensils / Ingredients / Storage Rack. One dark capsule holding three
/// labels; the selected one wears a cream capsule of its own.
struct StorageTabBar: View {

    @Binding var tab: StorageTab
    let geo: GeometryProxy

    static let frame = CGRect(x: 251, y: 41, width: 371, height: 29)

    var body: some View {
        let unit = StorageCanvas.scale(in: geo)

        HStack(spacing: 0) {
            ForEach(StorageTab.allCases) { entry in
                let selected = entry == tab
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { tab = entry }
                } label: {
                    Text(entry.title)
                        .font(.system(size: 12 * unit, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? StoragePalette.ink : StoragePalette.cream)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            // Only the selected tab gets a capsule. Drawing an
                            // invisible one under the other two and animating
                            // opacity looked like the pill was flickering.
                            if selected {
                                Capsule().fill(StoragePalette.cream)
                                    .shadow(color: .black.opacity(0.25),
                                            radius: 3 * unit, x: 0, y: 1 * unit)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? [.isSelected] : [])
            }
        }
        .padding(4 * unit)
        .background(Capsule().fill(Color.black.opacity(0.28)))
        .storagePlaced(Self.frame, in: geo)
    }
}

// MARK: - Clock

/// The alarm clock in the top-right corner, with the countdown drawn into its
/// face.
///
/// The kitchen's own clock is a SpriteKit node in the scene underneath, and
/// this overlay covers it — so without this the time simply disappears for as
/// long as a chef is at the pantry, which is exactly when they most want to
/// know it. The dial art ships empty for the same reason the scene's does:
/// the digits have to be ours to count down.
struct StorageClock: View {

    let timeRemaining: TimeInterval
    let geo: GeometryProxy

    static let frame = CGRect(x: 768, y: 24, width: 72, height: 79)

    private var text: String {
        let seconds = max(0, Int(timeRemaining))
        return String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    var body: some View {
        let unit = StorageCanvas.scale(in: geo)

        ZStack {
            if let art = UIImage(named: "timer") {
                Image(uiImage: art).resizable().scaledToFit()
            } else {
                Circle().fill(StoragePalette.cream)
                    .overlay(Circle().stroke(StoragePalette.ink, lineWidth: 3 * unit))
            }

            Text(text)
                .font(.system(size: 19 * unit, weight: .heavy, design: .rounded))
                // The last tenth of the round, matching `KitchenScene`'s own
                // rule rather than a fixed number of seconds.
                .foregroundStyle(timeRemaining < Recipe.timeLimit * 0.1
                                 ? Color(red: 0.78, green: 0.18, blue: 0.15)
                                 : StoragePalette.ink)
                // The dial is off-centre in the drawing: the two bells and the
                // handle take the top, so the face sits low.
                .offset(y: 4 * unit)
        }
        .storagePlaced(Self.frame, in: geo)
        .accessibilityLabel("Time remaining \(text)")
    }
}

// MARK: - Hands

/// The chef's paws along the bottom-right, holding whatever they carry.
///
/// Same drawing and the same relative positions as `StationHands`, restated
/// against the storage artboard. Both slots draw straight from the inventory
/// by id, so nothing here has to know which ingredient or tool it's showing.
struct StorageHands: View {

    @ObservedObject var inventory: PlayerInventory
    let geo: GeometryProxy

    var body: some View {
        ZStack {
            if let art = UIImage(named: "hands") {
                Image(uiImage: art).resizable().scaledToFit()
                    .storagePlaced(697, 305, 169, 97, alignment: .bottom, in: geo)
            }

            if let held = inventory.ingredient,
               let art = StorageArt.image(held.id) ?? FoodArt.art(held.id) {
                Image(uiImage: art).resizable().scaledToFit()
                    .storagePlaced(675, 287, 132, 79, alignment: .bottom, in: geo)
            }

            if let tool = inventory.utensil,
               let art = StorageArt.image(tool.id) ?? FoodArt.art(tool.id) {
                Image(uiImage: art).resizable().scaledToFit()
                    .storagePlaced(783, 273, 102, 93, alignment: .bottom, in: geo)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Caption

/// The line under the carousel: "Select your Ingredients".
struct StorageCaption: View {

    let text: String
    let geo: GeometryProxy

    static let frame = CGRect(x: 237, y: 332, width: 400, height: 30)

    var body: some View {
        Text(text)
            .font(.system(size: 22 * StorageCanvas.scale(in: geo),
                          weight: .heavy, design: .rounded))
            .foregroundStyle(StoragePalette.cream)
            .shadow(color: .black.opacity(0.55),
                    radius: 3 * StorageCanvas.scale(in: geo), x: 0, y: 1)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .storagePlaced(Self.frame, in: geo)
            .allowsHitTesting(false)
    }
}
