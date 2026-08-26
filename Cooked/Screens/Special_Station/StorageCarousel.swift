//
//  StorageCarousel.swift
//  Cooked
//
//  The picker used by the Utensils and Ingredients tabs of the storage room:
//  one item centred and large, its neighbours small either side, a chevron at
//  each end.
//
//  Why a carousel and not the list it replaced: a chef is at the pantry mid-
//  match with the clock running, and the list made every item a small tap
//  target with a name to read. Here there is one big thing in the middle and
//  the only question is whether it is the right one.
//

import SwiftUI

struct StorageCarouselItem: Identifiable, Equatable {
    let id: String
    let name: String
    /// Shown under the name — utensil stock, or nil for ingredients, which are
    /// drawn from an endless shelf.
    var detail: String? = nil
    /// True when the item is spoken for. Draws the dimmed `-in-use` art; the
    /// tap still goes through, so the caller can say why it did nothing.
    var isInUse: Bool = false
}

struct StorageCarousel: View {

    let items: [StorageCarouselItem]
    /// Index of the item in the middle. Owned by the caller so switching tabs
    /// and coming back doesn't lose your place.
    @Binding var index: Int
    var onPick: (StorageCarouselItem) -> Void

    private var focused: StorageCarouselItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 0) {
                arrow(.backward)

                // Three slots: previous, focused, next. Rendering only the
                // neighbours rather than the whole catalogue keeps the row a
                // fixed width, so the chevrons never move as you scroll.
                HStack(spacing: 4) {
                    slot(offset: -1)
                    slot(offset: 0)
                    slot(offset: 1)
                }
                .frame(maxWidth: .infinity)

                arrow(.forward)
            }
            .frame(height: StorageArt.focusedHeight + 24)

            if let focused {
                VStack(spacing: 2) {
                    Text(focused.name)
                        .font(.system(size: 22, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                    if let detail = focused.detail {
                        Text(detail)
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(AppTheme.ink.opacity(0.6))
                    }
                }
                // Swapping the text without this makes the whole row look like
                // it jumped, because the label resizes as the name changes.
                .animation(nil, value: index)
            }
        }
        .onAppear { clampIndex() }
        .onChange(of: items.count) { _, _ in clampIndex() }
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
    }

    // MARK: Pieces

    @ViewBuilder
    private func slot(offset: Int) -> some View {
        let position = index + offset
        if items.indices.contains(position) {
            let item = items[position]
            let isFocus = offset == 0
            let height = isFocus ? StorageArt.focusedHeight : StorageArt.unfocusedHeight

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
                artwork(for: item, height: height)
                    .frame(height: StorageArt.focusedHeight)
                    .frame(maxWidth: .infinity)
                    // Neighbours are context, not choices — dimming them keeps
                    // the eye on the middle.
                    .opacity(isFocus ? 1 : 0.55)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isFocus ? item.name : "Show \(item.name)")
        } else {
            // Keeps the three slots evenly spaced at the ends of the list.
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func artwork(for item: StorageCarouselItem, height: CGFloat) -> some View {
        Group {
            if let art = StorageArt.image(item.id, inUse: item.isInUse) {
                Image(uiImage: art)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: StorageArt.symbol(item.id))
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(AppTheme.ink.opacity(item.isInUse ? 0.25 : 0.8))
                    .padding(height * 0.15)
            }
        }
        .frame(height: height)
        .rotationEffect(StorageArt.tilt)
        // Focused items sit forward: a tighter, darker shadow. The blur radius
        // is what carries that, not the opacity.
        .shadow(color: .black.opacity(height == StorageArt.focusedHeight ? 0.38 : 0.18),
                radius: height == StorageArt.focusedHeight ? 10 : 16,
                x: 0,
                y: height == StorageArt.focusedHeight ? 8 : 5)
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: index)
    }

    private enum Direction { case backward, forward }

    @ViewBuilder
    private func arrow(_ direction: Direction) -> some View {
        let delta = direction == .forward ? 1 : -1
        let enabled = items.indices.contains(index + delta)
        Button { step(delta) } label: {
            Image(systemName: direction == .forward ? "chevron.right" : "chevron.left")
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(.white.opacity(enabled ? 0.95 : 0.25))
                .frame(width: 54, height: 54)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityLabel(direction == .forward ? "Next item" : "Previous item")
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
