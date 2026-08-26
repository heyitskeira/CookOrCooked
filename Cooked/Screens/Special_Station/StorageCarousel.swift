//
//  StorageCarousel.swift
//  Cooked
//
//  The picker used by the Utensils and Ingredients tabs: one item centred and
//  large, its neighbours small either side, a chevron at each end.
//
//  Why a carousel and not the list it replaced: a chef is at the pantry mid-
//  match with the clock running, and the list made every item a small tap
//  target with a name to read. Here there is one big thing in the middle and
//  the only question is whether it is the right one.
//
//  Both ends are hard stops, not a loop. The chevron that would walk past the
//  end is drawn faded and does nothing, so "am I at the start of the shelf" is
//  answerable at a glance instead of by flicking and watching what happens.
//

import SwiftUI

struct StorageCarouselItem: Identifiable, Equatable {
    let id: String
    let name: String
    /// Shown under the name — utensil stock, or nil for ingredients, which are
    /// drawn from an endless shelf.
    var detail: String? = nil
    /// True when the item is spoken for. Draws the dark `-inactive` silhouette;
    /// the tap still goes through, so the caller can say why it did nothing.
    var isInUse: Bool = false
}

struct StorageCarousel: View {

    let items: [StorageCarouselItem]
    /// Index of the item in the middle. Owned by the caller so switching tabs
    /// and coming back doesn't lose your place.
    @Binding var index: Int
    let geo: GeometryProxy
    var onPick: (StorageCarouselItem) -> Void

    // Every number below is in storage-artboard space — see `StorageCanvas`.

    /// Where the three item slots are centred, and how tall each is. The row's
    /// baseline is shared: a small neighbour and the big focused item are
    /// centred on the same line, which is what keeps the eye level as you
    /// scroll.
    private static let rowCentreY: CGFloat = 197
    private static let focusCentreX: CGFloat = 437
    private static let neighbourOffsetX: CGFloat = 167

    private static let leftArrowCentre = CGPoint(x: 170, y: 197)
    private static let rightArrowCentre = CGPoint(x: 704, y: 197)
    private static let arrowSide: CGFloat = 52

    var body: some View {
        ZStack {
            slot(offset: -1)
            slot(offset: 1)
            // Drawn last so the focused item overlaps its neighbours rather
            // than being clipped by them — they sit close enough to touch on
            // the widest art (the strawberry punnet).
            slot(offset: 0)

            arrow(.backward)
            arrow(.forward)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .contentShape(Rectangle())
        // Flick as well as tap the chevrons — the arrows are the discoverable
        // control, this is the one you end up using.
        .gesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    if value.translation.width < 0 { step(1) }
                    else if value.translation.width > 0 { step(-1) }
                }
        )
        .onAppear { clampIndex() }
        .onChange(of: items.count) { _, _ in clampIndex() }
    }

    // MARK: Pieces

    @ViewBuilder
    private func slot(offset: Int) -> some View {
        let position = index + offset
        if items.indices.contains(position) {
            let item = items[position]
            let isFocus = offset == 0
            let height = isFocus ? StorageArt.focusedHeight : StorageArt.unfocusedHeight
            let width = height * 1.35   // a generous box; the art fits inside it
            let x = Self.focusCentreX + CGFloat(offset) * Self.neighbourOffsetX

            Button {
                if isFocus {
                    // In-use items are still tappable on purpose. Dimming and
                    // then doing nothing leaves a chef prodding a dead item
                    // with no idea why; the caller answers with "someone else
                    // has it", which is the question they are actually asking.
                    onPick(item)
                } else {
                    step(offset)
                }
            } label: {
                artwork(for: item, isFocus: isFocus)
            }
            .buttonStyle(.plain)
            .storagePlaced(x - width / 2, Self.rowCentreY - height / 2, width, height, in: geo)
            // The design carries no item names — the drawing is the label,
            // and stock is told by full colour versus silhouette. VoiceOver
            // has neither, so it gets both spelled out here.
            .accessibilityLabel(isFocus ? item.name : "Show \(item.name)")
            .accessibilityValue(item.detail ?? "")
        }
    }

    @ViewBuilder
    private func artwork(for item: StorageCarouselItem, isFocus: Bool) -> some View {
        let unit = StorageCanvas.scale(in: geo)

        Group {
            if let art = StorageArt.image(item.id, inUse: item.isInUse) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: StorageArt.symbol(item.id))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(StoragePalette.cream.opacity(item.isInUse ? 0.25 : 0.8))
                    .padding(12 * unit)
            }
        }
        // Focused items sit forward: a tighter, darker shadow. The blur radius
        // is what carries that, not the opacity.
        .shadow(color: .black.opacity(isFocus ? 0.42 : 0.22),
                radius: (isFocus ? 9 : 14) * unit,
                x: 0,
                y: (isFocus ? 7 : 4) * unit)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: index)
    }

    private enum Direction { case backward, forward }

    @ViewBuilder
    private func arrow(_ direction: Direction) -> some View {
        let delta = direction == .forward ? 1 : -1
        let enabled = items.indices.contains(index + delta)
        let centre = direction == .forward ? Self.rightArrowCentre : Self.leftArrowCentre

        Button { step(delta) } label: {
            Image(systemName: direction == .forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 34 * StorageCanvas.scale(in: geo), weight: .bold))
                // The faded state is the end-of-shelf signal, so it has to be
                // clearly weaker than the live one and still clearly present —
                // an arrow that vanished would read as a layout bug.
                .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.22))
                .shadow(color: .black.opacity(enabled ? 0.5 : 0.2), radius: 4, x: 0, y: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .storagePlaced(centre.x - Self.arrowSide / 2, centre.y - Self.arrowSide / 2,
                       Self.arrowSide, Self.arrowSide, in: geo)
        .accessibilityLabel(direction == .forward ? "Next item" : "Previous item")
        .accessibilityHint(enabled ? "" : "End of the shelf")
    }

    private func step(_ delta: Int) {
        let next = index + delta
        guard items.indices.contains(next) else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.8)) { index = next }
    }

    /// Both catalogues are static today, so this never fires. It exists because
    /// without it a list that shrank below `index` would strand the carousel:
    /// nothing would be focused, and neither arrow could walk back into range,
    /// because `index - 1` would be out of bounds too.
    private func clampIndex() {
        guard !items.isEmpty else { return }
        if !items.indices.contains(index) {
            index = min(max(0, index), items.count - 1)
        }
    }
}
