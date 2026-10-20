//
//  CMusicApp.swift
//  CMusic
//
//  Created by Constantine Malynin on 2026-10-19.
//

import MusicKit
import SwiftUI

@main
struct CMusicApp: App {
    @State private var music = MusicService()
    @State private var player = PlayerModel()

    var body: some Scene {
        WindowGroup {
            MainView()
                .environment(music)
                .environment(player)
        }
        .defaultSize(width: 1200, height: 780)
        .commands {
            ControlsCommands(player: player)
        }
    }
}

/// The "Controls" menu in the menu bar, mirroring Music.app.
struct ControlsCommands: Commands {
    var player: PlayerModel

    var body: some Commands {
        CommandMenu("Controls") {
            Button(player.isPlaying ? "Pause" : "Play", action: player.togglePlayPause)
                .keyboardShortcut(.space, modifiers: [])
            Button("Next", action: player.next)
                .keyboardShortcut(.rightArrow, modifiers: .command)
            Button("Previous", action: player.previous)
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Divider()

            Toggle("Shuffle", isOn: Binding(get: { player.isShuffled }, set: { _ in player.toggleShuffle() }))
            Button("Repeat: \(repeatLabel)", action: player.cycleRepeat)
        }
    }

    private var repeatLabel: String {
        switch player.repeatMode {
        case .all: "All"
        case .one: "One"
        default: "Off"
        }
    }
}
