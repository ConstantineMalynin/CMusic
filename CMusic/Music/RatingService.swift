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
@Observable
final class RatingService {
    /// Ratings seen so far, so switching back to a song doesn't refetch it.
    private var cache: [MusicItemID: SongRating?] = [:]
    private(set) var errorMessage: String?

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
        }
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

    private static func isNotFound(_ error: Error) -> Bool {
        String(describing: error).contains("404")
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
