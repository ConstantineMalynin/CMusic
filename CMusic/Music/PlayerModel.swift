//
//  PlayerModel.swift
//  CMusic
//

import Combine
import Foundation
import MusicKit
import Observation

/// Observable bridge over `ApplicationMusicPlayer`, which publishes its state through Combine.
@Observable
final class PlayerModel {
    private(set) var isPlaying = false
    private(set) var title: String?
    private(set) var subtitle: String?
    private(set) var artwork: Artwork?
    private(set) var currentItemID: MusicItemID?
    private(set) var duration: TimeInterval = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: MusicPlayer.RepeatMode = .none
    private(set) var errorMessage: String?

    var hasCurrentEntry: Bool { title != nil }

    @ObservationIgnored private let player = ApplicationMusicPlayer.shared
    @ObservationIgnored private var stateObservation: AnyCancellable?
    @ObservationIgnored private var queueObservation: AnyCancellable?
    @ObservationIgnored private var clock: Task<Void, Never>?

    init() {
        stateObservation = player.state.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.sync() }
        observeQueue()
        sync()
    }

    /// `objectWillChange` fires before the change lands, hence the hop to the next run loop turn.
    private func observeQueue() {
        queueObservation = player.queue.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.sync() }
    }

    func clearError() {
        errorMessage = nil
    }

    // MARK: - Starting playback

    func play(_ songs: [Song], startingAt song: Song? = nil) {
        start(ApplicationMusicPlayer.Queue(for: songs, startingAt: song))
    }

    func play(_ tracks: [Track], startingAt track: Track? = nil) {
        start(ApplicationMusicPlayer.Queue(for: tracks, startingAt: track))
    }

    func play(_ item: some PlayableMusicItem) {
        start(ApplicationMusicPlayer.Queue(for: [item]))
    }

    func play(_ item: RecentlyPlayedMusicItem) {
        switch item {
        case .album(let album): play(album)
        case .playlist(let playlist): play(playlist)
        case .station(let station): play(station)
        @unknown default: break
        }
    }

    func play(_ item: MusicPersonalRecommendation.Item) {
        switch item {
        case .album(let album): play(album)
        case .playlist(let playlist): play(playlist)
        case .station(let station): play(station)
        @unknown default: break
        }
    }

    private func start(_ queue: ApplicationMusicPlayer.Queue) {
        player.queue = queue
        observeQueue()
        perform { try await self.player.play() }
    }

    // MARK: - Transport

    func togglePlayPause() {
        if isPlaying {
            player.pause()
        } else if hasCurrentEntry {
            perform { try await self.player.play() }
        }
    }

    func next() {
        perform { try await self.player.skipToNextEntry() }
    }

    func previous() {
        if player.playbackTime > 3 {
            player.restartCurrentEntry()
        } else {
            perform { try await self.player.skipToPreviousEntry() }
        }
    }

    func seek(to time: TimeInterval) {
        player.playbackTime = time
        elapsed = time
    }

    func toggleShuffle() {
        player.state.shuffleMode = isShuffled ? .off : .songs
    }

    func cycleRepeat() {
        player.state.repeatMode = switch repeatMode {
        case .none: .all
        case .all: .one
        default: MusicPlayer.RepeatMode.none
        }
    }

    // MARK: - State sync

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                errorMessage = nil
                try await operation()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func sync() {
        isPlaying = player.state.playbackStatus == .playing
        isShuffled = player.state.shuffleMode == .songs
        repeatMode = player.state.repeatMode ?? .none

        let entry = player.queue.currentEntry
        title = entry?.title
        subtitle = entry?.subtitle
        artwork = entry?.artwork
        switch entry?.item {
        case .song(let song):
            currentItemID = song.id
            duration = song.duration ?? 0
        case .musicVideo(let video):
            currentItemID = video.id
            duration = video.duration ?? 0
        default:
            currentItemID = nil
            duration = 0
        }
        elapsed = player.playbackTime
        isPlaying ? startClock() : stopClock()
    }

    /// `playbackTime` isn't observable, so poll it while playing.
    private func startClock() {
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.elapsed = self.player.playbackTime
            }
        }
    }

    private func stopClock() {
        clock?.cancel()
        clock = nil
    }
}

extension TimeInterval {
    /// Formats seconds as `m:ss`.
    var formattedDuration: String {
        let total = Int(self.rounded(.down))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
