//
//  TasteProfile.swift
//  CMusic
//

import Foundation
import MusicKit

/// What a listener's library says about them: which genres they play, who they play in each, and how
/// that is shifting. Built from library songs alone, so it needs no account beyond Apple Music.
struct TasteProfile: Equatable {
    var genres: [GenreTaste] = []
    var decades: [DecadeShare] = []
    var songCount = 0
    var totalPlays = 0
    /// Plays CMusic itself recorded, a subset of `totalPlays`.
    var historyPlays = 0
    var explicitShare: Double = 0
    var topArtists: [ArtistPlays] = []

    var isEmpty: Bool { genres.isEmpty }

    /// The decade with the largest share of plays, as "1990s".
    var favoriteDecade: String? {
        decades.max { $0.weight < $1.weight }.map(\.label)
    }

    /// One sentence summing up the top genres, for the page header.
    var headline: String {
        let names = genres.prefix(3).map(\.name)
        let topShare = genres.first?.share ?? 0
        switch names.count {
        case 0: return "Play some music to see what you're into."
        case 1: return "You're all about \(names[0])."
        case 2: return "Mostly \(names[0]), with a side of \(names[1])."
        case _ where topShare >= 0.5: return "You're a \(names[0]) person, with \(names[1]) and \(names[2]) on the side."
        case _ where topShare >= 0.2: return "Mostly \(names[0]), with \(names[1]) and \(names[2]) close behind."
        default: return "A bit of everything: \(names[0]), \(names[1]), \(names[2]) and more."
        }
    }
}

struct GenreTaste: Identifiable, Equatable {
    var name: String
    /// Broader genres these songs also belong to, most common first; the catalog charts are organized by these.
    var relatedGenres: [String]
    /// Share of all weighted plays, 0 to 1.
    var share: Double
    var plays: Int
    var songCount: Int
    var topArtists: [ArtistPlays]
    var topSongs: [Song]
    var trend: Trend

    var id: String { name }

    /// Whether recent listening leans toward this genre more or less than the library as a whole.
    enum Trend: Equatable {
        case rising, steady, fading
    }
}

struct ArtistPlays: Identifiable, Equatable {
    var name: String
    var plays: Int
    var id: String { name }
}

struct DecadeShare: Identifiable, Equatable {
    /// The first year of the decade, like 1990.
    var start: Int
    var weight: Double
    var id: Int { start }
    var label: String { "\(start)s" }
}

extension TasteProfile {
    /// Apple adds this catch-all to most songs; it says nothing about taste.
    private static let ignoredGenres: Set<String> = ["Music", "Música", "Musique", "Musik"]
    private static let recentWindow: TimeInterval = 90 * 24 * 60 * 60

    /// Combines two sources of plays. Library songs bring Music.app's play count, plus one so an unplayed
    /// library still produces a profile. CMusic's own listening history brings every song played here far
    /// enough to count, including catalog songs never added to the library. The same song in both is counted
    /// once, at the larger of the two play counts, since Apple may or may not have synced CMusic's plays.
    /// `genres` maps a library song ID to its genre names, most specific first.
    nonisolated init(songs: [Song], genres genreNames: [String: [String]], history: [ListeningHistory.Play] = [], now: Date = .now) {
        guard !songs.isEmpty || !history.isEmpty else { return }

        // One row per distinct song, keyed by title and artist so a library copy and its catalog twin merge.
        struct Entry {
            var song: Song
            var libraryPlays = 0
            var inLibrary = false
            var libraryRecent = false
            var historyPlays = 0
            var historyRecent = 0
            var names: [String] = []

            var weight: Int { max(libraryPlays, historyPlays) + (inLibrary ? 1 : 0) }
            var recentWeight: Int { historyRecent > 0 ? historyRecent : (libraryRecent ? libraryPlays : 0) }
        }
        func key(_ song: Song) -> String { "\(song.title)|\(song.artistName)".lowercased() }
        func isRecent(_ date: Date?) -> Bool { date.map { now.timeIntervalSince($0) < Self.recentWindow } ?? false }
        func cleaned(_ names: [String]) -> [String] { names.filter { !$0.isEmpty && !Self.ignoredGenres.contains($0) } }

        var entries: [String: Entry] = [:]
        var order: [String] = []
        for song in songs {
            let k = key(song)
            var entry = entries[k] ?? { order.append(k); return Entry(song: song) }()
            entry.song = song
            entry.inLibrary = true
            entry.libraryPlays += song.playCount ?? 0
            entry.libraryRecent = entry.libraryRecent || isRecent(song.lastPlayedDate)
            if entry.names.isEmpty { entry.names = cleaned(genreNames[song.id.rawValue] ?? song.genreNames) }
            entries[k] = entry
        }
        for play in history {
            let k = key(play.song)
            var entry = entries[k] ?? { order.append(k); return Entry(song: play.song) }()
            entry.historyPlays += 1
            if isRecent(play.date) { entry.historyRecent += 1 }
            // Catalog songs carry their genres; a library song's come from the genre map.
            if entry.names.isEmpty { entry.names = cleaned(genreNames[play.song.id.rawValue] ?? play.song.genreNames) }
            entries[k] = entry
        }

        struct Bucket {
            /// Weighted total: plays plus one per library song.
            var weight = 0
            /// Plays alone, for display.
            var plays = 0
            var recentPlays = 0
            var songCount = 0
            var artists: [String: Int] = [:]
            var related: [String: Int] = [:]
            var songs: [(Song, Int)] = []
        }
        var buckets: [String: Bucket] = [:]
        var artists: [String: Int] = [:]
        var decades: [Int: Double] = [:]
        var total = 0
        var recentTotal = 0
        var explicitWeight = 0
        var librarySongs = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current

        for k in order {
            guard let entry = entries[k] else { continue }
            let song = entry.song
            let weight = entry.weight
            let plays = max(entry.libraryPlays, entry.historyPlays)
            let recent = entry.recentWeight
            total += weight
            recentTotal += recent
            if entry.inLibrary { librarySongs += 1 }
            if song.contentRating == .explicit { explicitWeight += weight }
            if !song.artistName.isEmpty { artists[song.artistName, default: 0] += weight }
            if let year = song.releaseDate.map({ calendar.component(.year, from: $0) }), year > 1900 {
                decades[year / 10 * 10, default: 0] += Double(weight)
            }

            // The first name is the song's own genre; the rest are its parents, kept for chart lookups.
            guard let genre = entry.names.first else { continue }
            var bucket = buckets[genre, default: Bucket()]
            bucket.weight += weight
            bucket.plays += plays
            bucket.recentPlays += recent
            bucket.songCount += 1
            if !song.artistName.isEmpty { bucket.artists[song.artistName, default: 0] += weight }
            bucket.songs.append((song, weight))
            for parent in entry.names.dropFirst() { bucket.related[parent, default: 0] += weight }
            buckets[genre] = bucket
        }

        let genreTotal = max(buckets.values.reduce(0) { $0 + $1.weight }, 1)
        self.genres = buckets.map { name, bucket in
            let share = Double(bucket.weight) / Double(genreTotal)
            let recentShare = recentTotal > 0 ? Double(bucket.recentPlays) / Double(recentTotal) : share
            let trend: GenreTaste.Trend = if recentTotal == 0 || bucket.recentPlays == 0 && bucket.weight < 10 {
                .steady
            } else if recentShare > share * 1.3 + 0.02 {
                .rising
            } else if recentShare < share * 0.7 - 0.02 {
                .fading
            } else {
                .steady
            }
            return GenreTaste(
                name: name,
                relatedGenres: Self.ranked(bucket.related, limit: 3).map(\.name),
                share: share,
                plays: bucket.plays,
                songCount: bucket.songCount,
                topArtists: Self.ranked(bucket.artists, limit: 5),
                topSongs: bucket.songs.sorted { $0.1 > $1.1 }.prefix(10).map(\.0),
                trend: trend
            )
        }
        .sorted { $0.share > $1.share || ($0.share == $1.share && $0.name < $1.name) }

        let decadeTotal = max(decades.values.reduce(0, +), 1)
        self.decades = decades.map { DecadeShare(start: $0.key, weight: $0.value / decadeTotal) }.sorted { $0.start < $1.start }
        self.songCount = order.count
        self.totalPlays = total - librarySongs
        self.historyPlays = history.count
        self.explicitShare = Double(explicitWeight) / Double(total)
        self.topArtists = Self.ranked(artists, limit: 10)
    }

    private nonisolated static func ranked(_ counts: [String: Int], limit: Int) -> [ArtistPlays] {
        counts.map { ArtistPlays(name: $0.key, plays: $0.value) }
            .sorted { $0.plays > $1.plays || ($0.plays == $1.plays && $0.name < $1.name) }
            .prefix(limit)
            .map { $0 }
    }
}
