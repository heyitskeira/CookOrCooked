//
//  KitchenArt.swift
//  Cooked
//
//  Loading the kitchen map's artwork, and the measurements that place the two
//  pieces of HUD chrome that sit on top of it.
//
//  Every number in `KitchenArt` was measured against the reference mockup at
//  `Asset-Final/Screens/09-kitchen/screen-09-kitchen-head-chef.png` (3496x1608)
//  by locating each exported sprite inside it. They are fractions of the scene
//  rather than points so the layout survives any screen size — the same trick
//  `StationID.unitPosition` uses, and for the same reason.
//

import SpriteKit
import UIKit

extension SKTexture {

    /// A map texture by asset-catalogue name, or nil if it isn't in the bundle.
    ///
    /// `SKTexture(imageNamed:)` never fails — a missing asset gives back a
    /// placeholder texture that renders as a grey box, which looks like a bug
    /// in the art rather than a missing file. Going through `UIImage` first
    /// gives the caller a real nil to branch on, so the scene can fall back to
    /// its pre-art appearance instead.
    static func kitchenArt(_ name: String) -> SKTexture? {
        guard let image = UIImage(named: name) else { return nil }
        return SKTexture(image: image)
    }
}

/// `nonisolated` so the geometry is callable from anywhere.
///
/// Under SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor a bare enum — and every
/// static member on it — is main-actor isolated. `ServeRitual` is `nonisolated`
/// for the same reason `StationID` is, and it needs `mapRect` to size the serve
/// circle, so this has to be reachable from a nonisolated context. Everything
/// here is arithmetic over value types, so there is nothing to protect.
nonisolated enum KitchenArt {

    // MARK: The map

    /// The aspect ratio the map art was drawn at (1748x804).
    static let mapAspect: CGFloat = 1748.0 / 804.0

    /// Where the background image lands on screen. Everything painted onto the
    /// map — the props, their stone pads, the serve stone — is positioned
    /// against *this* rect rather than against the scene, and both axes share
    /// one scale factor.
    ///
    /// Sizing props by `unit * scene.width` and `unit * scene.height`
    /// separately is only correct while the screen happens to share the art's
    /// aspect ratio. A phone in landscape (≈2.168) passes; iPad (1.43 landscape,
    /// 0.70 portrait) does not, and independent scaling there stretches every
    /// prop and slides it off the pad painted underneath it.
    ///
    /// The art is scaled to **fit**, not to fill. Filling would crop the left
    /// and right edges on iPad — and the edges are where things live: the bin
    /// at unit x 0.095, the clock at 0.928, the recipe book at 0.086 would all
    /// end up off-screen. A chef holding something rotten is locked out of
    /// every station except the bin, so a bin they cannot reach is a chef who
    /// cannot play. Letterboxing costs a band of background above and below on
    /// a tablet, and about a point of it on a phone.
    static func mapRect(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        let width: CGFloat
        let height: CGFloat
        if size.width / size.height > mapAspect {
            // Screen is wider than the art: match heights, bars left and right.
            height = size.height
            width = size.height * mapAspect
        } else {
            width = size.width
            height = size.width / mapAspect
        }
        return CGRect(x: (size.width - width) / 2,
                      y: (size.height - height) / 2,
                      width: width, height: height)
    }

    /// A point measured on the artboard, in scene coordinates. `unit.y` counts
    /// up from the bottom, as everywhere else in SpriteKit.
    static func mapPoint(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        let rect = mapRect(in: size)
        return CGPoint(x: rect.minX + unit.x * rect.width,
                       y: rect.minY + unit.y * rect.height)
    }

    /// The inverse of `mapPoint` — a scene point back to artboard units.
    ///
    /// This is what chef positions travel in. They used to be scene-relative,
    /// which agreed with the stations while those were scene-relative too; now
    /// that stations are placed on the artboard, a position sent as a fraction
    /// of the screen would land somewhere else on a device with a different
    /// aspect ratio, and chefs would appear beside stations rather than at them.
    static func mapUnit(_ point: CGPoint, in size: CGSize) -> CGPoint {
        let rect = mapRect(in: size)
        guard rect.width > 0, rect.height > 0 else { return .zero }
        return CGPoint(x: (point.x - rect.minX) / rect.width,
                       y: (point.y - rect.minY) / rect.height)
    }

    /// A size measured on the artboard, in scene coordinates.
    static func mapSize(_ unit: CGSize, in size: CGSize) -> CGSize {
        let rect = mapRect(in: size)
        return CGSize(width: unit.width * rect.width,
                      height: unit.height * rect.height)
    }

    // MARK: Timer

    /// The alarm clock, top right.
    static let clockUnitCentre = CGPoint(x: 0.9279, y: 0.8483)
    static let clockUnitSize   = CGSize(width: 0.0938, height: 0.2239)

    /// The centre of the clock's *face*, which is not the centre of the sprite:
    /// the bells sit above it. The countdown is drawn here, so it lands inside
    /// the dial rather than across the casing.
    static let clockFaceUnitCentre = CGPoint(x: 0.9279, y: 0.8380)

    /// The dial is a little under two thirds of the sprite's width, and the
    /// countdown has to fit inside it at any screen size.
    static let clockFaceWidthFraction: CGFloat = 0.62

    // MARK: Recipe book button

    /// The hanging book sign, top left. Head chef only — see `KitchenGameView`.
    ///
    /// This uses `btn-recipe-book-map`, cut from the mockup, rather than the
    /// exported `btn-recipe-book`: the export carries a much longer post
    /// (104x268, so a 0.39 aspect against the sign's 0.66) and would hang down
    /// past the tree line. Swap back once a matching export exists.
    static let bookUnitCentre = CGPoint(x: 0.0860, y: 0.9027)
    static let bookUnitSize   = CGSize(width: 0.0581, height: 0.1909)

    /// The sign's frame in **SwiftUI** coordinates (y down from the top), since
    /// that is the one piece of this layout SwiftUI draws rather than SpriteKit.
    ///
    /// Measured against the artboard like everything else, so it stays on the
    /// tree it hangs from.
    static func bookFrame(in size: CGSize) -> CGRect {
        let rect = mapRect(in: size)
        let box = mapSize(bookUnitSize, in: size)
        let centreX = rect.minX + bookUnitCentre.x * rect.width
        // `bookUnitCentre.y` counts up from the bottom, as everywhere else here,
        // so it has to be flipped for SwiftUI.
        let centreY = size.height - (rect.minY + bookUnitCentre.y * rect.height)
        return CGRect(x: centreX - box.width / 2,
                      y: centreY - box.height / 2,
                      width: box.width, height: box.height)
    }
}
