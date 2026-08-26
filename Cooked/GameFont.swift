//
//  GameFont.swift
//  Cooked
//
//  The game's type, in one place.
//
//  We use SF Pro, which is the system font — so this reaches it through
//  `Font.system`, never through a bundled file. Apple's licence permits using
//  SF Pro via the system APIs on Apple platforms but **not** redistributing it
//  inside an app bundle, so the `.otf` files from Apple's developer downloads
//  are for mockups and Figma, not for the target.
//
//  The screen mockups letter their headings in a heavy condensed cut. That is
//  reachable on SF Pro through the weight and width axes — `.black` weight,
//  `.condensed` width — rather than needing a separate display face.
//
//  Note `design: .default`, not `.rounded`. SF Rounded is a different face;
//  the headings in the mockups are straight-sided SF Pro.
//

import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum GameFont {

    /// Headings: SETTINGS, TODAY'S ORDER, station plaques.
    ///
    /// Drawn by `ArchedTitle`, which adds the arc, the outline and the shadow.
    enum Display {

        static let weight: Font.Weight = .black

        /// SF Pro's width axis. The reference lettering is tighter than the
        /// standard cut; `.condensed` gets most of the way there and
        /// `ArchedTitle` squeezes the rest to hit the exact word width.
        ///
        /// If a heading still reads too wide, `.compressed` is the next step
        /// in — change it here and every heading follows.
        static let width: Font.Width = .condensed

        static func font(size: CGFloat) -> Font {
            .system(size: size, weight: weight, design: .default)
            .width(width)
        }

        /// Point size that puts the capitals at `capHeight`.
        ///
        /// Measured off the font itself rather than hard-coded, so it stays
        /// correct if the weight changes or Apple revises the metrics. The
        /// width axis doesn't affect cap height, so the probe ignores it.
        static func size(forCapHeight capHeight: CGFloat) -> CGFloat {
            capHeight / capHeightRatio
        }

        /// Cap height as a fraction of point size — about 0.70 for SF Pro.
        ///
        /// Probed from the font rather than hard-coded, so it survives a
        /// metrics revision. Neither weight nor width moves SF Pro's cap
        /// height, so the probe doesn't bother setting them.
        static var capHeightRatio: CGFloat {
            #if canImport(UIKit)
            let ratio = UIFont.systemFont(ofSize: 100).capHeight / 100
            return ratio > 0 ? ratio : 0.70
            #else
            return 0.70
            #endif
        }
    }

    /// Interface text sitting on the painted panels — slider labels, button
    /// captions. Same family as the headings, lighter and unwarped.
    enum Label {
        static func font(size: CGFloat) -> Font {
            .system(size: size, weight: .bold, design: .default)
        }

        static func size(forCapHeight capHeight: CGFloat) -> CGFloat {
            capHeight / Display.capHeightRatio
        }
    }
}
