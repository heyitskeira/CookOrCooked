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

    /// How far a finger must travel before it counts as looking along the
    /// shelf rather than choosing what it landed on. Device points, not
    /// artboard units — this is about fingers, which are the same size on
    /// every screen.
    private static let flickDistance: CGFloat = 12

    var body: some View {
        ZStack {
            // One view per *item*, not one per slot.
            //
            // The shelf used to be three fixed boxes that swapped their
            // contents when the index moved. Nothing could animate that: as far
            // as SwiftUI was concerned the middle box had simply been handed a
            // different picture, so it cut to it. That was the blink — the
            // items never travelled, they were re-dealt.
            //
            // Keyed by position in `items`, each drawing keeps its identity
            // across a step and only its x and its size change. Those are both
            // animatable, so the same tap now slides the shelf along.
            ForEach(window, id: \.self) { position in
                itemView(at: position)
            }

            arrow(.backward)
            arrow(.forward)
        }
        .frame(width: geo.size.width, height: geo.size.height)
        .contentShape(Rectangle())
        // Flick as well as tap the chevrons — the arrows are the discoverable
        // control, this is the one you end up using.
        //
        // `highPriorityGesture`, not `gesture`, and 12 rather than 24. Between
        // them those two were why the shelf felt like it grabbed things: an
        // ordinary `.gesture` sits *below* the item buttons, so any flick the
        // drag hadn't claimed yet went to whichever item was under the finger
        // and picked it up. With a 24-point threshold that was every flick
        // shorter than 24 points, which is most of them — the chef swiped to
        // look along the shelf and walked away holding something.
        //
        // Now the drag outranks the buttons and claims the touch after half
        // that distance. A tap is still a tap: a drag with a minimum distance
        // never starts from a finger that doesn't travel, so it cannot eat the
        // deliberate press it is protecting.
        .highPriorityGesture(
            DragGesture(minimumDistance: Self.flickDistance)
                .onEnded { value in
                    if value.translation.width < 0 { step(1) }
                    else if value.translation.width > 0 { step(-1) }
                }
        )
        .onAppear { clampIndex() }
        .onChange(of: items.count) { _, _ in clampIndex() }
    }

    // MARK: Pieces

    /// The items close enough to the middle to be worth drawing.
    ///
    /// One wider than you can see, on each side. The extra pair is what stops
    /// the item arriving from off-shelf appearing out of nowhere at the
    /// neighbour position: it already exists, parked out of sight, so a step
    /// slides it in rather than fading it up.
    private var window: [Int] {
        items.indices.filter { abs($0 - index) <= 2 }
    }

    @ViewBuilder
    private func itemView(at position: Int) -> some View {
        let item = items[position]
        let steps = position - index          // -2 … +2, and it is a CGFloat below
        let distance = CGFloat(steps)
        let isFocus = steps == 0
        // Only the middle item and its two neighbours are on the shelf. The
        // outer pair is staged off it — invisible, and deliberately not
        // tappable, or a chef could pick something they cannot see.
        let isOnShelf = abs(steps) <= 1

        let height = isFocus ? StorageArt.focusedHeight : StorageArt.unfocusedHeight
        let width = height * 1.35   // a generous box; the art fits inside it
        let x = Self.focusCentreX + distance * Self.neighbourOffsetX

        Button {
            if isFocus {
                // In-use items are still tappable on purpose. Dimming and
                // then doing nothing leaves a chef prodding a dead item
                // with no idea why; the caller answers with "someone else
                // has it", which is the question they are actually asking.
                onPick(item)
            } else {
                step(steps)
            }
        } label: {
            artwork(for: item, isFocus: isFocus)
        }
        .buttonStyle(.plain)
        .storagePlaced(x - width / 2, Self.rowCentreY - height / 2, width, height, in: geo)
        .opacity(isOnShelf ? 1 : 0)
        .allowsHitTesting(isOnShelf)
        // The focused item rides over its neighbours rather than being clipped
        // by them. Ordering the `ForEach` cannot do this — it runs in position
        // order, and which position is focused keeps changing — so depth is
        // stated per item instead.
        .zIndex(-abs(Double(steps)))
        // The design carries no item names — the drawing is the label,
        // and stock is told by full colour versus silhouette. VoiceOver
        // has neither, so it gets both spelled out here.
        .accessibilityLabel(isFocus ? item.name : "Show \(item.name)")
        .accessibilityValue(item.detail ?? "")
        .accessibilityHidden(!isOnShelf)
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
        // No `.animation(value: index)` here any more. It was the only
        // animation on the shelf back when the slots were fixed, which is why
        // it was written against `index` — but a nested animation on the label
        // now fights the one `step` runs around the whole change, and the two
        // together are what made the size pop while the position slid.
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
        withAnimation(Self.slide) { index = next }
    }

    /// How the shelf moves.
    ///
    /// `.smooth` is a spring with no bounce, which is what a shelf of heavy
    /// objects should do — the old `.spring(dampingFraction: 0.8)` overshot
    /// slightly, and on an item the size of the focused one that reads as a
    /// wobble rather than as weight. Springs also retarget cleanly when they
    /// are interrupted, so holding down a chevron runs the items along in one
    /// continuous movement instead of restarting the animation per tap.
    private static let slide: Animation = .smooth(duration: 0.32)

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
