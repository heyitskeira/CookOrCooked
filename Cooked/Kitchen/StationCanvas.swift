//
//  StationCanvas.swift
//  Cooked
//
//  The one piece of geometry every illustrated station page shares: the Figma
//  artboard its art was measured against, and how to put a design-space rect
//  onto whatever size the device actually gives us.
//
//  Lifted out of `ChoppingStationView` when the bowl station became the second
//  page built this way. Same idea as `StationID.unitPosition`, which does it
//  for a single point on the kitchen map — this does it for a whole rect.
//

import SwiftUI

enum StationCanvas {

    /// The artboard every station's (x, y, w, h) numbers are stated against.
    ///
    /// This is NOT any background PNG's own pixel size — the forest background
    /// is stretched to bleed past the artboard on every edge, so its raw size
    /// (874x402) is a different box entirely. The artboard is the stretched
    /// frame: origin (-22, -81), size (919.18, 513). Every element's x/y is in
    /// that same shared space, so a negative number (the back button's
    /// y = -56, for one) is still on-screen — it only reads as off-screen if
    /// you mistake (0, 0) for the origin, which pushes everything above the
    /// real top edge.
    static let origin = CGPoint(x: -22, y: -81)
    static let size = CGSize(width: 919.18, height: 513)

    /// Design-space rect → device-space rect, for the rare caller that needs
    /// the numbers rather than a placed view (laying children out inside a
    /// region, say). `figmaPlaced` below is what most code wants.
    static func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     in geo: GeometryProxy) -> CGRect {
        let sx = geo.size.width / size.width
        let sy = geo.size.height / size.height
        return CGRect(x: (x - origin.x) * sx, y: (y - origin.y) * sy,
                      width: w * sx, height: h * sy)
    }

    /// Same, for a frame kept as a named constant.
    static func rect(_ frame: CGRect, in geo: GeometryProxy) -> CGRect {
        rect(frame.minX, frame.minY, frame.width, frame.height, in: geo)
    }
}

extension View {

    /// Place this view at a Figma-measured rect, scaled to the device.
    ///
    /// `alignment` matters whenever the art's own aspect ratio doesn't match
    /// the given box: `.scaledToFit()` then renders smaller than the box on
    /// one axis, and by default SwiftUI centers that slack on both sides. For
    /// anything meant to sit flush against an edge (hands resting on the
    /// bottom of the screen, say), centering puts half the slack on the wrong
    /// side and the art visibly floats off that edge — pass the edge it should
    /// hug instead.
    func figmaPlaced(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat,
                     alignment: Alignment = .center, in geo: GeometryProxy) -> some View {
        let box = StationCanvas.rect(x, y, w, h, in: geo)
        return self
            .frame(width: box.width, height: box.height, alignment: alignment)
            .position(x: box.midX, y: box.midY)
    }

    /// Same, for a frame kept as a named constant.
    func figmaPlaced(_ frame: CGRect, alignment: Alignment = .center,
                     in geo: GeometryProxy) -> some View {
        figmaPlaced(frame.minX, frame.minY, frame.width, frame.height,
                    alignment: alignment, in: geo)
    }
}
