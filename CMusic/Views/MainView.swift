//
//  MainView.swift
//  CMusic
//

import AppKit
import MusicKit
import SwiftUI

/// The main window: sidebar navigation, detail content and the player toolbar.
struct MainView: View {
    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player
    @Environment(RatingService.self) private var ratings
    @Environment(ListeningHistory.self) private var history
    @State private var selection: SidebarItem? = .home
    @State private var path = NavigationPath()
    @State private var searchText = ""
    /// `nil` while a search is in flight.
    @State private var searchResults: SearchResults? = SearchResults()
    /// Where the sidebar was before a search cleared its selection, restored when the search is emptied.
    @State private var selectionBeforeSearch: SidebarItem?

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $selection, playlists: music.libraryPlaylists)
        } detail: {
            NavigationStack(path: $path) {
                Group {
                    if music.isAuthorized {
                        detail
                    } else {
                        AuthorizationView()
                    }
                }
                .navigationDestination(for: Destination.self, destination: destinationView)
            }
            .frame(minWidth: 520, maxWidth: .infinity, maxHeight: .infinity)
        }
        .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
        // Below the whole split view, so the toolbar's leading edge is left to the back button.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                PlayerBar(player: player, openArtist: openCurrentArtist)
            }
        }
        .onChange(of: selection) { _, selection in
            path = NavigationPath()
            // Choosing a sidebar item leaves the search results.
            if selection != nil, !searchText.isEmpty { searchText = "" }
        }
        // Searching clears the sidebar highlight, like Music.app, so clicking any item (even the previous
        // one) is a change that leaves the search.
        .onChange(of: searchText.isEmpty) { _, isEmpty in
            if !isEmpty {
                if selection != nil {
                    selectionBeforeSearch = selection
                    selection = nil
                }
            } else if selection == nil {
                selection = selectionBeforeSearch ?? .home
            }
        }
        .task { await music.refreshAll() }
        .onAppear { player.onSongListened = { [history] song in history.record(song) } }
        // Coming back to the app after a while gives Home a fresh arrangement, like Music.app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await music.refreshHomeIfStale() }
        }
        .task(id: searchText) {
            searchResults = nil
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            let results = await music.search(searchText)
            guard !Task.isCancelled else { return }
            searchResults = results
        }
        .alert(
            "Playback Error",
            isPresented: Binding(get: { player.errorMessage != nil }, set: { if !$0 { player.clearError() } }),
            actions: {},
            message: { Text(player.errorMessage ?? "") }
        )
        .alert(
            "Rating Error",
            isPresented: Binding(get: { ratings.errorMessage != nil }, set: { if !$0 { ratings.clearError() } }),
            actions: {},
            message: { Text(ratings.errorMessage ?? "") }
        )
    }

    @ViewBuilder
    private var detail: some View {
        if !searchText.isEmpty {
            SearchView(term: searchText, results: searchResults)
        } else {
            switch selection ?? .home {
            case .home: HomeView()
            case .new: NewView()
            case .radio: RadioView()
            case .cjsr: LiveStreamView(stream: .cjsr)
            case .taste:
                TasteView(
                    songs: music.librarySongs,
                    genres: music.libraryGenres,
                    isLoadingGenres: !music.loadedSections.contains(.genres)
                )
                .librarySection(.songs, isEmpty: music.librarySongs.isEmpty, item: .songs)
                .task(id: music.libraryGeneration) { await music.load(.genres) }
            case .recentlyAdded:
                ItemGridView(title: "Recently Added", items: music.recentlyAdded) { player.play($0) }
                    .librarySection(.recentlyAdded, isEmpty: music.recentlyAdded.isEmpty, item: .recentlyAdded)
            case .artists:
                ArtistsView(artists: music.libraryArtists)
                    .librarySection(.artists, isEmpty: music.libraryArtists.isEmpty, item: .artists)
            case .albums:
                ItemGridView(title: "Albums", items: music.libraryAlbums) { player.play($0) }
                    .librarySection(.albums, isEmpty: music.libraryAlbums.isEmpty, item: .albums)
            case .songs:
                SongsView(songs: music.librarySongs)
                    .librarySection(.songs, isEmpty: music.librarySongs.isEmpty, item: .songs)
            case .madeForYou:
                ItemGridView(title: "Made for You", items: music.recommendations.flatMap(\.playlists)) { player.play($0) }
            case .musicVideos:
                ItemGridView(title: "Music Videos", items: music.libraryMusicVideos) { player.play([Track.musicVideo($0)]) }
                    .librarySection(.musicVideos, isEmpty: music.libraryMusicVideos.isEmpty, item: .musicVideos)
            case .allPlaylists:
                ItemGridView(title: "All Playlists", items: music.libraryPlaylists) { player.play($0) }
            case .playlist(let id):
                if let playlist = music.libraryPlaylists.first(where: { $0.id == id }) {
                    CollectionDetailView(playlist: playlist, music: music).id(id)
                }
            }
        }
    }

    /// Pushes the playing song's artist page, like clicking the artist name in Music.app.
    private func openCurrentArtist() {
        guard let song = player.currentSong else { return }
        Task {
            if let artist = await music.artist(for: song) {
                path.append(Destination.artist(artist))
            }
        }
    }

    @ViewBuilder
    private func destinationView(_ destination: Destination) -> some View {
        switch destination {
        case .album(let album): CollectionDetailView(album: album, music: music)
        case .playlist(let playlist): CollectionDetailView(playlist: playlist, music: music)
        case .artist(let artist): ArtistDetailView(artist: artist).id(artist.id)
        }
    }
}

/// Prompts for MusicKit access, or explains how to grant it after a denial.
struct AuthorizationView: View {
    @Environment(MusicService.self) private var music

    var body: some View {
        ContentUnavailableView {
            Label("Connect to Apple Music", systemImage: "music.note")
        } description: {
            switch music.authorization {
            case .denied, .restricted:
                Text("CMusic doesn't have access to Apple Music. Allow it in System Settings › Privacy & Security › Media & Apple Music.")
            default:
                Text("Sign in with your Apple Music account to browse and play your library.")
            }
        } actions: {
            switch music.authorization {
            case .denied, .restricted:
                Link("Open System Settings", destination: URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Media")!)
            default:
                Button("Continue") { Task { await music.requestAccess() } }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}
