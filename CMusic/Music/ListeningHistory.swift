//
//  ListeningHistory.swift
//  CMusic
//

import Foundation
import MusicKit
import Observation
import os

private let logger = Logger(subsystem: "com.localStuff.CMusic", category: "ListeningHistory")

/// Every song CMusic has played far enough to count, kept on disk so the Taste page can learn from
/// listening Apple doesn't report back: catalog songs never added to the library, and plays Music.app
/// hasn't synced. Local to this Mac and this app.
@Observable
final class ListeningHistory {
    struct Play: Codable, Identifiable, Equatable {
        var id: UUID
        var song: Song
        var date: Date
    }

    private(set) var plays: [Play] = []
    private(set) var isLoaded = false

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultFileURL
        Task { await load() }
    }

    private static var defaultFileURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return support.appending(path: "CMusic/history.json")
    }

    /// Adds one play of `song`, now, and schedules a save.
    func record(_ song: Song, at date: Date = .now) {
        plays.append(Play(id: UUID(), song: song, date: date))
        scheduleSave()
    }

    func clear() {
        plays = []
        scheduleSave()
    }

    private func load() async {
        let url = fileURL
        let loaded: [Play] = await Task.detached {
            guard let data = try? Data(contentsOf: url) else { return [] }
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try decoder.decode([Play].self, from: data)
            } catch {
                logger.error("history unreadable: \(String(describing: error), privacy: .public)")
                return []
            }
        }.value
        // Plays recorded while the file was loading come after the ones on disk.
        plays = loaded + plays
        isLoaded = true
    }

    /// Writes shortly after the last change, so a burst of skips produces one write.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [plays, fileURL] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await Task.detached {
                do {
                    let encoder = JSONEncoder()
                    encoder.dateEncodingStrategy = .iso8601
                    let data = try encoder.encode(plays)
                    try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try data.write(to: fileURL, options: .atomic)
                } catch {
                    logger.error("history save failed: \(String(describing: error), privacy: .public)")
                }
            }.value
        }
    }
}
