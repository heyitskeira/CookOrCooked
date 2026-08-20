//
//  EndGameResults.swift
//  Cooked
//
//  Win/lose result + star score, shown when the game ends. Reads the game-over
//  state off the snapshot (didWin, timeRemaining) — no netcode. A "Back to
//  start" button unwinds the whole flow to the start screen.
//

import SwiftUI

extension Notification.Name {
    /// Posted to collapse every cover back to the start screen.
    static let returnToStart = Notification.Name("cooked.returnToStart")
}

// MARK: - Scoring

enum EndScore {
    /// Stars from how fast the cake was finished, as a fraction of the limit:
    /// within 50% → 3, within 80% → 2, slower → 1. A loss is 0.
    static func stars(didWin: Bool,
                      timeRemaining: TimeInterval,
                      timeLimit: TimeInterval = Recipe.timeLimit) -> Int {
        guard didWin, timeLimit > 0 else { return 0 }
        let fraction = (timeLimit - timeRemaining) / timeLimit
        if fraction <= 0.5 { return 3 }
        if fraction <= 0.8 { return 2 }
        return 1
    }
}

// MARK: - Result screen

struct EndGameResultsView: View {
    let didWin: Bool
    let timeRemaining: TimeInterval
    var timeLimit: TimeInterval = Recipe.timeLimit
    var onBackToStart: () -> Void

    private var stars: Int {
        EndScore.stars(didWin: didWin, timeRemaining: timeRemaining, timeLimit: timeLimit)
    }
    private var elapsed: TimeInterval { max(0, timeLimit - timeRemaining) }

    var body: some View {
        ZStack {
            AppTheme.background

            ScrollView {
                VStack(spacing: 28) {
                    Text(didWin ? "Cake finished" : "Cake is not cake-ing")
                        .font(.system(size: 40, weight: .heavy, design: .rounded))
                        .foregroundStyle(AppTheme.ink)
                        .multilineTextAlignment(.center)

                    starsRow

                    if didWin {
                        Text("Completed in \(timeString(elapsed))")
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(AppTheme.ink.opacity(0.7))
                    }

                    PillButton(
                        title: "Back to start",
                        style: .filled(background: AppTheme.tomato, foreground: AppTheme.cream)
                    ) { onBackToStart() }
                    .frame(maxWidth: 300)
                    .padding(.top, 8)
                }
                .padding(40)
                .frame(maxWidth: .infinity)
            }
        }
        .ignoresSafeArea()
    }

    private var starsRow: some View {
        HStack(spacing: 18) {
            ForEach(0..<3, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .font(.system(size: 56, weight: .bold))
                    .foregroundStyle(i < stars
                                     ? Color(red: 0.98, green: 0.78, blue: 0.20)
                                     : AppTheme.ink.opacity(0.25))
                    .scaleEffect(i < stars ? 1 : 0.85)
            }
        }
    }

    private func timeString(_ t: TimeInterval) -> String {
        let s = Int(t.rounded())
        return String(format: "%d:%02d", s / 60, s % 60)
    }
}

#Preview("3 stars") {
    EndGameResultsView(didWin: true, timeRemaining: Recipe.timeLimit * 0.7, onBackToStart: {})
}
