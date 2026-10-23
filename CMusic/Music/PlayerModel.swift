//
//  PlayerModel.swift
//  CMusic
//

import AVFoundation
import Combine
import Foundation
import MediaPlayer
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
    /// The song that is playing, when the current entry is one; used to reach its artist page.
    private(set) var currentSong: Song?
    private(set) var duration: TimeInterval = 0
    private(set) var elapsed: TimeInterval = 0
    private(set) var isShuffled = false
    private(set) var repeatMode: MusicKit.MusicPlayer.RepeatMode = .none
    private(set) var errorMessage: String?
    /// The internet radio station that is playing instead of the Apple Music queue, if any.
    private(set) var liveStream: LiveStream?

    /// When the queue reaches its last song, follow it with that song's station, like Music.app's ∞.
    var autoplay = UserDefaults.standard.object(forKey: "autoplay") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoplay, forKey: "autoplay") }
    }

    var hasCurrentEntry: Bool { title != nil }

    @ObservationIgnored private let player = ApplicationMusicPlayer.shared
    @ObservationIgnored private var streamPlayer: AVPlayer?
    @ObservationIgnored private var streamObservation: NSKeyValueObservation?
    /// Media-key handlers registered while a stream plays; MusicKit handles the keys for its own queue.
    @ObservationIgnored private var remoteCommandTargets: [(MPRemoteCommand, Any)] = []
    @ObservationIgnored private var stateObservation: AnyCancellable?
    @ObservationIgnored private var queueObservation: AnyCancellable?
    @ObservationIgnored private var clock: Task<Void, Never>?
    @ObservationIgnored private var autoplayTask: Task<Void, Never>?
    /// Set once per queue: after the station is queued, or when the queue is a station to begin with.
    @ObservationIgnored private var autoplayHandled = false

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
        start(ApplicationMusicPlayer.Queue(for: [item]), isStation: item is Station)
    }

    func play(_ item: RecentlyPlayedMusicItem) {
        switch item {
        case .album(let album): play(album)
        case .playlist(let playlist): play(playlist)
        case .station(let station): play(station)
        @unknown default: break
        }
    }

    func play(_ item: MusicCatalogSearchResponse.TopResult) {
        switch item {
        case .song(let song): play([song])
        case .album(let album): play(album)
        case .playlist(let playlist): play(playlist)
        case .station(let station): play(station)
        case .musicVideo(let video): play([Track.musicVideo(video)])
        default: break
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

    /// Plays an internet radio station, replacing whatever Apple Music was playing.
    func play(_ stream: LiveStream) {
        if liveStream == stream {
            streamPlayer?.play()
            return
        }
        stopStream()
        player.pause()
        errorMessage = nil

        let item = AVPlayerItem(url: stream.url)
        let avPlayer = AVPlayer(playerItem: item)
        streamPlayer = avPlayer
        liveStream = stream
        streamObservation = avPlayer.observe(\.timeControlStatus, options: [.initial, .new]) { [weak self] _, _ in
            Task { @MainActor in self?.syncStream() }
        }
        avPlayer.play()
        registerRemoteCommands()
        syncStream()
    }

    // MARK: - Media keys for the stream

    /// Without a Now Playing registration the play/pause key opens Music.app, so claim it for the stream.
    private func registerRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        func handle(_ command: MPRemoteCommand, _ action: @escaping () -> Void) {
            let target = command.addTarget { [weak self] _ in
                guard self?.liveStream != nil else { return .noActionableNowPlayingItem }
                action()
                return .success
            }
            remoteCommandTargets.append((command, target))
        }
        handle(center.togglePlayPauseCommand) { [weak self] in self?.togglePlayPause() }
        handle(center.playCommand) { [weak self] in
            guard let self, !self.isPlaying else { return }
            self.togglePlayPause()
        }
        handle(center.pauseCommand) { [weak self] in self?.streamPlayer?.pause() }
        for command in [center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand] {
            command.isEnabled = false
        }
    }

    private func unregisterRemoteCommands() {
        for (command, target) in remoteCommandTargets {
            command.removeTarget(target)
        }
        remoteCommandTargets = []
        let center = MPRemoteCommandCenter.shared()
        for command in [center.nextTrackCommand, center.previousTrackCommand, center.changePlaybackPositionCommand] {
            command.isEnabled = true
        }
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = nil
        info.playbackState = .stopped
    }

    private func updateNowPlaying(for stream: LiveStream) {
        let info = MPNowPlayingInfoCenter.default()
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: stream.name,
            MPMediaItemPropertyArtist: stream.subtitle,
            MPNowPlayingInfoPropertyIsLiveStream: true,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0,
        ]
        info.playbackState = isPlaying ? .playing : .paused
    }

    /// Tears down the radio stream, so the Apple Music queue is what the bar shows again.
    private func stopStream() {
        guard liveStream != nil else { return }
        unregisterRemoteCommands()
        streamObservation = nil
        streamPlayer?.pause()
        streamPlayer = nil
        liveStream = nil
        sync()
    }

    private func start(_ queue: ApplicationMusicPlayer.Queue, isStation: Bool = false) {
        stopStream()
        autoplayTask?.cancel()
        autoplayTask = nil
        autoplayHandled = isStation
        seed = nil
        player.queue = queue
        observeQueue()
        perform { try await self.player.play() }
    }

    // MARK: - Transport

    func togglePlayPause() {
        if let streamPlayer {
            if isPlaying {
                streamPlayer.pause()
            } else {
                // A paused live stream has fallen behind; rejoining live is what a radio does.
                streamPlayer.seek(to: .positiveInfinity)
                streamPlayer.play()
            }
        } else if isPlaying {
            player.pause()
        } else if hasCurrentEntry {
            perform { try await self.player.play() }
        }
    }

    /// Skipping past the last song queues the autoplay station first, so skip continues into it
    /// instead of wrapping to the start of the queue.
    func next() {
        guard liveStream == nil else { return }
        perform {
            if self.isOnLastEntry, self.autoplay, self.repeatMode == .none {
                await self.queueStationNow()
            }
            try await self.player.skipToNextEntry()
        }
    }

    func previous() {
        guard liveStream == nil else { return }
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
        default: MusicKit.MusicPlayer.RepeatMode.none
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

    /// Mirrors the radio stream into the same fields the Apple Music queue fills.
    private func syncStream() {
        guard let liveStream, let streamPlayer else { return }
        isPlaying = streamPlayer.timeControlStatus != .paused
        title = liveStream.name
        subtitle = liveStream.subtitle
        artwork = nil
        currentItemID = nil
        currentSong = nil
        duration = 0
        elapsed = 0
        stopClock()
        updateNowPlaying(for: liveStream)
        if let error = streamPlayer.currentItem?.error ?? streamPlayer.error {
            errorMessage = error.localizedDescription
        }
    }

    private func sync() {
        // While a radio stream plays, the idle Apple Music queue must not take over the bar.
        guard liveStream == nil else { return }
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
            currentSong = song
            duration = song.duration ?? 0
        case .musicVideo(let video):
            currentItemID = video.id
            currentSong = nil
            duration = video.duration ?? 0
        default:
            currentItemID = nil
            currentSong = nil
            duration = 0
        }
        elapsed = player.playbackTime
        isPlaying ? startClock() : stopClock()
        skipRepeatedSeedSong()
    }

    // MARK: - Autoplay

    /// Appends the current song's station near the end of the last entry, so it follows on without a gap.
    /// Waits for the final seconds because an album or playlist queue starts out as a single entry
    /// and only fills in its tracks once playback begins.
    private func queueStationIfAtEnd() {
        guard autoplay, !autoplayHandled, autoplayTask == nil, repeatMode == .none,
              duration > 0, duration - elapsed < 20, isOnLastEntry
        else { return }
        startQueueingStation()
    }

    private var isOnLastEntry: Bool {
        guard let entry = player.queue.currentEntry else { return false }
        return entry.id == player.queue.entries.last?.id
    }

    /// Queues the station right away, joining the near-the-end attempt if it is already running.
    private func queueStationNow() async {
        if autoplayTask == nil, !autoplayHandled {
            startQueueingStation()
        }
        await autoplayTask?.value
    }

    private func startQueueingStation() {
        guard let entry = player.queue.currentEntry, case .song(let song) = entry.item else { return }
        autoplayTask = Task { [weak self] in
            let station = try? await Self.station(for: song)
            guard let self, !Task.isCancelled else { return }
            // One attempt per queue, so a song with no station doesn't retry on every tick.
            self.autoplayHandled = true
            if let station, (try? await self.player.queue.insert(station, position: .tail)) != nil {
                self.seed = (entry.id, song.title)
            }
            self.autoplayTask = nil
        }
    }

    /// The entry a station was queued after, and its title.
    @ObservationIgnored private var seed: (entryID: String, title: String)?

    /// A song's station opens with that same song, so skip it rather than play it twice.
    private func skipRepeatedSeedSong() {
        guard let seed, let entry = player.queue.currentEntry, entry.id != seed.entryID,
              case .song(let song) = entry.item
        else { return }
        self.seed = nil
        if song.title == seed.title {
            next()
        }
    }

    /// The song's own station, falling back to its artist's. Library songs are first matched to the catalog.
    private static func station(for song: Song) async throws -> Station? {
        guard let catalogSong = try await catalogSong(for: song) else { return nil }
        let detailed = try await catalogSong.with([.station, .artists])
        if let station = detailed.station { return station }
        return try await detailed.artists?.first?.with([.station]).station
    }

    private static func catalogSong(for song: Song) async throws -> Song? {
        var byID = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: song.id)
        byID.limit = 1
        if let match = try? await byID.response().items.first { return match }

        if let isrc = song.isrc {
            var byISRC = MusicCatalogResourceRequest<Song>(matching: \.isrc, equalTo: isrc)
            byISRC.limit = 1
            if let match = try await byISRC.response().items.first { return match }
        }

        var search = MusicCatalogSearchRequest(term: "\(song.title) \(song.artistName)", types: [Song.self])
        search.limit = 5
        return try await search.response().songs.first {
            $0.title.localizedCaseInsensitiveCompare(song.title) == .orderedSame
                && $0.artistName.localizedCaseInsensitiveCompare(song.artistName) == .orderedSame
        }
    }

    /// `playbackTime` isn't observable, so poll it while playing.
    private func startClock() {
        guard clock == nil else { return }
        clock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self else { return }
                self.elapsed = self.player.playbackTime
                self.queueStationIfAtEnd()
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
