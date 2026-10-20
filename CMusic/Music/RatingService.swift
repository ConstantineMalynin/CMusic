//
//  RatingService.swift
//  CMusic
//

import Foundation
import MusicKit
import os

private let logger = Logger(subsystem: "com.localStuff.CMusic", category: "RatingService")

/// Love or dislike, as Apple Music stores it against a song.
enum SongRating: Int, Codable {
    case liked = 1
    case disliked = -1
}

/// Reads and writes song ratings through the Apple Music API's `me/ratings` endpoint, which MusicKit
/// doesn't wrap. Ratings sync to the user's Apple Music account like Music.app's Love/Suggest Less.
///
/// Liked songs are also collected in a playlist the app owns, since Apple's own Favourite Songs
/// playlist can't be added to through the API.
@Observable
final class RatingService {
    static let likesPlaylistName = "CMusic Likes"

    /// Ratings seen so far, so switching back to a song doesn't refetch it.
    private var cache: [MusicItemID: SongRating?] = [:]
    private(set) var errorMessage: String?
    @ObservationIgnored private let music: MusicService
    @ObservationIgnored private var likesPlaylistID: String? {
        get { UserDefaults.standard.string(forKey: "likesPlaylistID") }
        set { UserDefaults.standard.set(newValue, forKey: "likesPlaylistID") }
    }

    init(music: MusicService) {
        self.music = music
    }

    func rating(for song: Song) -> SongRating? {
        cache[song.id] ?? nil
    }

    func load(_ song: Song) async {
        if cache[song.id] != nil { return }
        var request = URLRequest(url: Self.url(for: song))
        request.httpMethod = "GET"
        do {
            let response = try await MusicDataRequest(urlRequest: request).response()
            let decoded = try JSONDecoder().decode(RatingResponse.self, from: response.data)
            cache[song.id] = decoded.data.first.map(\.attributes.value)
        } catch {
            // A song with no rating comes back as 404, which is the normal case.
            cache[song.id] = .some(nil)
            if !Self.isNotFound(error) {
                logger.error("rating fetch failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// Sets the rating, or clears it when the song already has that rating.
    func toggle(_ rating: SongRating, for song: Song) async {
        let current = self.rating(for: song)
        let next: SongRating? = current == rating ? nil : rating
        cache[song.id] = .some(next)
        var request = URLRequest(url: Self.url(for: song))
        if let next {
            request.httpMethod = "PUT"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(RatingBody(attributes: .init(value: next)))
        } else {
            request.httpMethod = "DELETE"
        }
        do {
            _ = try await MusicDataRequest(urlRequest: request).response()
        } catch {
            cache[song.id] = .some(current)
            logger.error("rating update failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't save the rating: \(error.localizedDescription)"
            return
        }

        // Keep the likes playlist in step: a like adds the song, anything else removes it.
        do {
            if next == .liked {
                try await addToLikes(song)
            } else if current == .liked {
                try await removeFromLikes(song)
            }
            scheduleSidebarRefresh()
        } catch {
            logger.error("likes playlist update failed: \(String(describing: error), privacy: .public)")
            errorMessage = "Couldn't update the \(Self.likesPlaylistName) playlist: \(Self.describe(error))"
        }
    }

    // MARK: - Likes playlist

    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    /// The sidebar hides empty playlists and reads the local library, which takes a while to sync a change
    /// made through the API or Music.app, so it is refreshed a few times after each edit.
    private func scheduleSidebarRefresh() {
        refreshTask?.cancel()
        refreshTask = Task { [music] in
            for delay in [2, 15, 45, 90] {
                try? await Task.sleep(for: .seconds(delay))
                guard !Task.isCancelled else { return }
                await music.reloadPlaylists()
            }
        }
    }

    private static let library = URL(string: "https://api.music.apple.com/v1/me/library/playlists")!

    private func addToLikes(_ song: Song) async throws {
        if let id = try await existingLikesPlaylistID() {
            let tracksURL = Self.library.appending(path: "\(id)/tracks")
            // Liking a song that is already listed (after an un-like Music.app hasn't synced yet) must not duplicate it.
            guard try await !playlistTracks(id).contains(where: { $0.matches(song) }) else { return }
            try await send("POST", tracksURL, body: TracksBody(data: [.init(song)]))
        } else {
            let body = NewPlaylistBody(
                attributes: .init(name: Self.likesPlaylistName, description: "Songs liked in CMusic"),
                relationships: .init(tracks: TracksBody(data: [.init(song)]))
            )
            let data = try await send("POST", Self.library, body: body)
            likesPlaylistID = try JSONDecoder().decode(PlaylistsResponse.self, from: data).data.first?.id
        }
    }

    /// An empty playlist answers 404 rather than an empty list.
    private func playlistTracks(_ id: String) async throws -> [TracksResponse.Item] {
        do {
            let data = try await send("GET", Self.library.appending(path: "\(id)/tracks").appending(queryItems: [.init(name: "limit", value: "100")]))
            return try JSONDecoder().decode(TracksResponse.self, from: data).data
        } catch let error as MusicDataRequest.Error where error.status == 404 {
            return []
        }
    }

    /// The Apple Music API accepts track deletions but never applies them, so removal goes through Music.app,
    /// which edits the synced playlist directly. Needs the Apple Events entitlement and the user's one-time consent.
    /// A song liked moments ago may not have synced into Music.app yet, so the script retries for a while.
    private func removeFromLikes(_ song: Song) async throws {
        guard try await existingLikesPlaylistID() != nil else { return }
        let script = """
        tell application "Music"
            if not (exists user playlist "\(Self.likesPlaylistName)") then return 0
            set matches to (every track of user playlist "\(Self.likesPlaylistName)" whose name is "\(song.title.escapedForAppleScript)" and artist is "\(song.artistName.escapedForAppleScript)")
            set matchCount to count of matches
            repeat with t in matches
                delete t
            end repeat
            return matchCount
        end tell
        """
        for attempt in 0..<7 {
            if attempt > 0 { try await Task.sleep(for: .seconds(5)) }
            var error: NSDictionary?
            let result = NSAppleScript(source: script)?.executeAndReturnError(&error)
            if let error {
                let message = error[NSAppleScript.errorMessage] as? String ?? "\(error)"
                throw NSError(domain: "CMusic.AppleScript", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
            }
            if (result?.int32Value ?? 0) > 0 { return }
        }
    }

    /// The saved playlist id, re-validated against the library in case the user deleted the playlist.
    private func existingLikesPlaylistID() async throws -> String? {
        if let id = likesPlaylistID {
            if (try? await send("GET", Self.library.appending(path: id))) != nil { return id }
            likesPlaylistID = nil
        }
        if let match = music.libraryPlaylists.first(where: { $0.name == Self.likesPlaylistName }) {
            likesPlaylistID = match.id.rawValue
            return match.id.rawValue
        }
        return nil
    }

    @discardableResult
    private func send(_ method: String, _ url: URL, body: (some Encodable)? = Optional<TracksBody>.none) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = method
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(body)
        }
        return try await MusicDataRequest(urlRequest: request).response().data
    }

    func clearError() {
        errorMessage = nil
    }

    /// Library songs (ids starting with "i.") are rated through `library-songs`; catalog songs through `songs`.
    private static func url(for song: Song) -> URL {
        let id = song.id.rawValue
        let kind = id.hasPrefix("i.") ? "library-songs" : "songs"
        return URL(string: "https://api.music.apple.com/v1/me/ratings/\(kind)/\(id)")!
    }

    /// Apple's API errors carry a status and detail that `localizedDescription` hides.
    private static func describe(_ error: Error) -> String {
        if let error = error as? MusicDataRequest.Error {
            return "HTTP \(error.status) \(error.title): \(error.detailText)"
        }
        return error.localizedDescription
    }

    private static func isNotFound(_ error: Error) -> Bool {
        (error as? MusicDataRequest.Error)?.status == 404
    }
}

private struct RatingResponse: Decodable {
    struct Item: Decodable {
        struct Attributes: Decodable { var value: SongRating }
        var attributes: Attributes
    }
    var data: [Item]
}

private struct RatingBody: Encodable {
    struct Attributes: Encodable { var value: SongRating }
    var type = "rating"
    var attributes: Attributes
}

private struct TracksBody: Encodable {
    struct Item: Encodable {
        var id: String
        var type: String

        init(id: String, type: String) {
            self.id = id
            self.type = type
        }

        init(_ song: Song) {
            id = song.id.rawValue
            type = id.hasPrefix("i.") ? "library-songs" : "songs"
        }
    }
    var data: [Item]
}

private struct NewPlaylistBody: Encodable {
    struct Attributes: Encodable { var name: String; var description: String }
    struct Relationships: Encodable { var tracks: TracksBody }
    var attributes: Attributes
    var relationships: Relationships
}

private struct PlaylistsResponse: Decodable {
    struct Item: Decodable { var id: String }
    var data: [Item]
}

private struct TracksResponse: Decodable {
    struct Item: Decodable {
        struct Attributes: Decodable {
            struct PlayParams: Decodable { var catalogId: String? }
            var playParams: PlayParams?
        }
        var id: String
        var attributes: Attributes?

        /// Playlist tracks carry library ids, so a catalog song is matched through its catalog id.
        func matches(_ song: Song) -> Bool {
            id == song.id.rawValue || attributes?.playParams?.catalogId == song.id.rawValue
        }
    }
    var data: [Item]
}

private extension String {
    var escapedForAppleScript: String {
        replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}
