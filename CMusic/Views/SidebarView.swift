//
//  SidebarView.swift
//  CMusic
//

import MusicKit
import SwiftUI

enum SidebarItem: Hashable {
    case home, new, radio, cjsr
    case recentlyAdded, artists, albums, songs, madeForYou, musicVideos
    case allPlaylists
    case playlist(Playlist.ID)

    var title: String {
        switch self {
        case .home: "Home"
        case .new: "New"
        case .radio: "Radio"
        case .cjsr: LiveStream.cjsr.name
        case .recentlyAdded: "Recently Added"
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .madeForYou: "Made for You"
        case .musicVideos: "Music Videos"
        case .allPlaylists: "All Playlists"
        case .playlist: "Playlist"
        }
    }

    var symbol: String {
        switch self {
        case .home: "house"
        case .new: "square.grid.2x2"
        case .radio: "dot.radiowaves.left.and.right"
        case .cjsr: "antenna.radiowaves.left.and.right"
        case .recentlyAdded: "clock"
        case .artists: "music.microphone"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .madeForYou: "person.crop.square"
        case .musicVideos: "music.note.tv"
        case .allPlaylists: "square.grid.3x3"
        case .playlist: "music.note.list"
        }
    }

    static let discover: [SidebarItem] = [.home, .new, .radio, .cjsr]
    static let library: [SidebarItem] = [.recentlyAdded, .artists, .albums, .songs, .madeForYou, .musicVideos]
}

struct SidebarView: View {
    @Binding var selection: SidebarItem?
    var playlists: [Playlist]

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(SidebarItem.discover, id: \.self, content: row)
            }

            Section("Library") {
                ForEach(SidebarItem.library, id: \.self, content: row)
            }

            Section("Playlists") {
                row(.allPlaylists)
                ForEach(playlists) { playlist in
                    Label(playlist.name, systemImage: "music.note.list")
                        .tag(SidebarItem.playlist(playlist.id))
                }
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 300)
    }

    private func row(_ item: SidebarItem) -> some View {
        Label(item.title, systemImage: item.symbol)
            .tag(item)
    }
}
