//
//  CookedApp.swift
//  Cooked
//
//  Created by Keira on 10/08/26.
//

import SwiftUI

@main
struct CookedApp: App {

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            StartScreenView()
                // One place starts the audio session and the menu loop. Doing
                // it per-screen would restart the music every time somebody
                // backed out of the lobby.
                .onAppear { Music.shared.start() }
        }
        // Coming back from the background, a phone call, or Siri. iOS stops
        // playback on the way out and doesn't restart it on the way in —
        // without this the music is gone for the rest of the launch.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Music.shared.resume() }
        }
    }
}
