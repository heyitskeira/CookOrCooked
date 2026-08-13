//
//  Theme.swift
//  Cooked
//
//  Shared visual language for the Cook or Cooked screens.
//

import SwiftUI

enum AppTheme {
    // Palette pulled from the Cook or Cooked logo
    static let cream = Color(red: 0.97, green: 0.92, blue: 0.83)
    static let creamDeep = Color(red: 0.94, green: 0.86, blue: 0.72)
    static let tomato = Color(red: 0.91, green: 0.27, blue: 0.24)
    static let ink = Color(red: 0.13, green: 0.11, blue: 0.10)

    // Warm kitchen backdrop used across screens
    static var background: some View {
        LinearGradient(
            colors: [creamDeep, cream],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }
}

// MARK: - Pill Button

struct PillButton: View {
    enum Style {
        case filled(background: Color, foreground: Color)
        case outlined(background: Color, foreground: Color)
    }

    let title: String
    let style: Style
    var ink: Color = AppTheme.ink
    let action: () -> Void

    @State private var pressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 26, weight: .bold, design: .rounded))
                .foregroundStyle(foreground)
                .frame(maxWidth: .infinity)
                .frame(height: 72)
                .background(
                    Capsule().fill(background)
                )
                .overlay(
                    Capsule().stroke(ink, lineWidth: 3)
                )
                .shadow(color: ink.opacity(0.25), radius: pressed ? 2 : 6,
                        x: 0, y: pressed ? 2 : 5)
                .offset(y: pressed ? 3 : 0)
        }
        .buttonStyle(.plain)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }

    private var background: Color {
        switch style {
        case .filled(let bg, _): return bg
        case .outlined(let bg, _): return bg
        }
    }

    private var foreground: Color {
        switch style {
        case .filled(_, let fg): return fg
        case .outlined(_, let fg): return fg
        }
    }
}
