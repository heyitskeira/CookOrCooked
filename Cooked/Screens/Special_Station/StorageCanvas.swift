//
//  StorageCanvas.swift
//  Cooked
//
//  The design space the storage room is laid out in, and how a design-space
//  rect lands on whatever size the device actually gives us.
//
//  Same idea as `StationCanvas`, different artboard. The illustrated station
//  pages are measured against a *stretched* frame (origin (-22, -81), size
//  919x513) because the forest background bleeds past the screen on every
//  edge. The storage frames don't: `ui-storage-bg` is exactly 874x402 at 1x
//  and fills its frame corner to corner, so this artboard is the plain screen
//  and its origin really is (0, 0). Feeding storage numbers to `figmaPlaced`
//  would shift everything down and right by the station artboard's bleed.
//
//  Frames: "storage room: utensils view", "storage room: ingredients view",
//  "storage room: storage rack view" — all 874 x 402.
//

import SwiftUI

enum StorageCanvas {

    /// The artboard every (x, y, w, h) in the storage room is stated against.
    static let size = CGSize(width: 874, height: 402)

    /// Design-space rect → device-space rect, for callers that need the
    /// numbers rather than a placed view.
    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     in geo: GeometryProxy) -> CGRect {
        let sx = geo.size.width / size.width
        let sy = geo.size.height / size.height
        return CGRect(x: x * sx, y: y * sy, width: w * sx, height: h * sy)
    }

    static func rect(_ frame: CGRect, in geo: GeometryProxy) -> CGRect {
        rect(frame.minX, frame.minY, frame.width, frame.height, in: geo)
    }

    /// How much one design unit is worth on this device, for the few things
    /// that scale rather than sit at a measured rect — type sizes, mostly.
    static func scale(in geo: GeometryProxy) -> CGFloat {
        min(geo.size.width / size.width, geo.size.height / size.height)
    }
}

extension View {

    /// Place this view at a storage-artboard rect, scaled to the device.
    ///
    /// `alignment` matters when the art's aspect ratio doesn't match the box:
    /// `.scaledToFit` then leaves slack on one axis, which SwiftUI centres by
    /// default. Anything meant to rest on a surface — a prep sitting on a
    /// shelf plank — wants `.bottom` instead, or it floats.
    func storagePlaced(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                       alignment: Alignment = .center, in geo: GeometryProxy) -> some View {
        let box = StorageCanvas.rect(x, y, w, h, in: geo)
        return self
            .frame(width: box.width, height: box.height, alignment: alignment)
            .position(x: box.midX, y: box.midY)
    }

    func storagePlaced(_ frame: CGRect, alignment: Alignment = .center,
                       in geo: GeometryProxy) -> some View {
        storagePlaced(frame.minX, frame.minY, frame.width, frame.height,
                      alignment: alignment, in: geo)
    }
}
