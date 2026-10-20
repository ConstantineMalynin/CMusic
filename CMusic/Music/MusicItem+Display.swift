//
//  MusicItem+Display.swift
//  CMusic
//

import Foundation
import MusicKit

/// Common display fields so shelves and grids can render any MusicKit item.
protocol TileDisplayable: Identifiable {
    var tileTitle: String { get }
    var tileSubtitle: String { get }
    var tileArtwork: Artwork? { get }
}

extension Album: TileDisplayable {
    var tileTitle: String { title }
    var tileSubtitle: String { artistName }
    var tileArtwork: Artwork? { artwork }
}

extension Playlist: TileDisplayable {
    var tileTitle: String { name }
    var tileSubtitle: String { curatorName ?? "Playlist" }
    var tileArtwork: Artwork? { artwork }
}

extension Station: TileDisplayable {
    var tileTitle: String { name }
    var tileSubtitle: String { isLive ? "Live" : "Station" }
    var tileArtwork: Artwork? { artwork }
}

extension Song: TileDisplayable {
    var tileTitle: String { title }
    var tileSubtitle: String { artistName }
    var tileArtwork: Artwork? { artwork }
}

extension Artist: TileDisplayable {
    var tileTitle: String { name }
    var tileSubtitle: String { "" }
    var tileArtwork: Artwork? { artwork }
}

extension MusicVideo: TileDisplayable {
    var tileTitle: String { title }
    var tileSubtitle: String { artistName }
    var tileArtwork: Artwork? { artwork }
}

extension RecentlyPlayedMusicItem: TileDisplayable {
    private var wrapped: (any TileDisplayable)? {
        switch self {
        case .album(let album): album
        case .playlist(let playlist): playlist
        case .station(let station): station
        @unknown default: nil
        }
    }

    var tileTitle: String { wrapped?.tileTitle ?? "" }
    var tileSubtitle: String { wrapped?.tileSubtitle ?? "" }
    var tileArtwork: Artwork? { wrapped?.tileArtwork }
}

extension MusicPersonalRecommendation.Item: TileDisplayable {
    private var wrapped: (any TileDisplayable)? {
        switch self {
        case .album(let album): album
        case .playlist(let playlist): playlist
        case .station(let station): station
        @unknown default: nil
        }
    }

    var tileTitle: String { wrapped?.tileTitle ?? "" }
    var tileSubtitle: String { wrapped?.tileSubtitle ?? "" }
    var tileArtwork: Artwork? { wrapped?.tileArtwork }
}

/// A flattened row for the song tables, built from either a `Song` or a `Track`.
struct TrackRow: Identifiable, Equatable {
    var id: MusicItemID
    var title: String
    var artist: String
    var album: String
    var duration: TimeInterval
    var artwork: Artwork?
    var isExplicit: Bool

    init(_ song: Song) {
        id = song.id
        title = song.title
        artist = song.artistName
        album = song.albumTitle ?? ""
        duration = song.duration ?? 0
        artwork = song.artwork
        isExplicit = song.contentRating == .explicit
    }

    init(_ track: Track) {
        id = track.id
        title = track.title
        artist = track.artistName
        album = track.albumTitle ?? ""
        duration = track.duration ?? 0
        artwork = track.artwork
        isExplicit = track.contentRating == .explicit
    }
}
