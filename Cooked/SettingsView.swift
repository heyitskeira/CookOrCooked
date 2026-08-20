//
//  SettingsView.swift
//  Cooked
//
//  What the gear on the start screen opens.
//
//  Music and sound effects are two separate switches on purpose. Plenty of
//  people turn the music off and keep the effects — being told "audio: off" as
//  a single choice is the thing that makes them turn the lot off instead.
//

import SwiftUI

struct SettingsView: View {

    @ObservedObject private var music = Music.shared
    @ObservedObject private var effects = SoundFX.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            AppTheme.background

            VStack(spacing: 18) {
                Text("Settings")
                    .font(.system(size: 30, weight: .heavy, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                    .padding(.bottom, 4)

                SoundRow(title: "Music",
                         subtitle: "Menu and kitchen loops",
                         onIcon: "music.note",
                         isOn: Binding(get: { !music.isMuted },
                                       set: { music.isMuted = !$0 }))

                SoundRow(title: "Sound effects",
                         subtitle: "Taps, chopping, serving",
                         onIcon: "waveform",
                         isOn: Binding(get: { !effects.isMuted },
                                       set: { effects.isMuted = !$0 }))

                PillButton(title: "Done",
                           style: .filled(background: AppTheme.tomato,
                                          foreground: AppTheme.cream)) {
                    dismiss()
                }
                .padding(.top, 8)
            }
            .frame(maxWidth: 460)
            .padding(.horizontal, 40)
            .padding(.vertical, 24)
        }
    }
}

// MARK: - One switch

private struct SoundRow: View {

    let title: String
    let subtitle: String
    /// Shown while the switch is on; it becomes a struck-through speaker when
    /// off, so the state reads without having to find the toggle.
    let onIcon: String

    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: isOn ? onIcon : "speaker.slash.fill")
                .font(.system(size: 21, weight: .bold))
                .foregroundStyle(AppTheme.cream)
                .frame(width: 48, height: 48)
                .background(Circle().fill(isOn ? AppTheme.tomato : Color.gray))
                .overlay(Circle().stroke(AppTheme.ink, lineWidth: 3))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 19, weight: .bold, design: .rounded))
                    .foregroundStyle(AppTheme.ink)
                Text(subtitle)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(AppTheme.ink.opacity(0.5))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 8)

            // Bound inverted at the call site, so the switch reads the way a
            // player expects: on means you can hear it.
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .tint(AppTheme.tomato)
        }
        .padding(.horizontal, 18)
        .frame(height: 80)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(AppTheme.cream)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.ink, lineWidth: 3)
        )
    }
}

#Preview {
    SettingsView()
}
