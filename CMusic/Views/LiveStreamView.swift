//
//  LiveStreamView.swift
//  CMusic
//

import SwiftUI

/// The page for an internet radio station: it starts playing when opened, with a play/pause control.
struct LiveStreamView: View {
    var stream: LiveStream
    @Environment(PlayerModel.self) private var player

    private var isCurrent: Bool { player.liveStream == stream }
    private var isPlaying: Bool { isCurrent && player.isPlaying }

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 64))
                .foregroundStyle(isPlaying ? Color.accentColor : Color.secondary)
                .symbolEffect(.variableColor.iterative, isActive: isPlaying)

            VStack(spacing: 4) {
                Text(stream.name).font(.title).fontWeight(.semibold)
                Text(stream.subtitle).foregroundStyle(.secondary)
            }

            Button(isPlaying ? "Pause" : "Listen Live", systemImage: isPlaying ? "pause.fill" : "play.fill") {
                if isCurrent {
                    player.togglePlayPause()
                } else {
                    player.play(stream)
                }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Link("Visit \(stream.website.host() ?? "website")", destination: stream.website)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(stream.name)
        .onAppear {
            if !isCurrent { player.play(stream) }
        }
    }
}
