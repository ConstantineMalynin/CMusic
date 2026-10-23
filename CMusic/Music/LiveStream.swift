//
//  LiveStream.swift
//  CMusic
//

import Foundation

/// An internet radio station outside Apple Music, played with AVPlayer instead of MusicKit.
struct LiveStream: Hashable, Identifiable {
    var id: String { url.absoluteString }
    var name: String
    var subtitle: String
    var url: URL
    var website: URL

    /// CJSR 88.5 FM, the University of Alberta's campus and community station in Edmonton.
    static let cjsr = LiveStream(
        name: "CJSR (Edmonton)",
        subtitle: "CJSR 88.5 FM · Live Radio",
        url: URL(string: "https://ais-sa1.streamon.fm/7093_24k.aac")!,
        website: URL(string: "https://www.cjsr.com")!
    )
}
