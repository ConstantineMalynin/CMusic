//
//  TasteView.swift
//  CMusic
//

import AppKit
import MusicKit
import SwiftUI

/// "Your Taste": a breakdown of the library by genre, with the listener's most played in each genre
/// and what is popular there right now.
struct TasteView: View {
    var songs: [Song]
    /// Genre names per library song ID, from `MusicService.libraryGenres`.
    var genres: [String: [String]]
    var isLoadingGenres: Bool

    @Environment(PlayerModel.self) private var player
    @Environment(ListeningHistory.self) private var history
    @State private var profile: TasteProfile?
    @State private var confirmsClear = false

    /// How many genres get a full section; the rest fold into "Other" in the bar.
    private static let sectionCount = 6

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 36) {
                if let profile, !profile.isEmpty {
                    TasteHeader(profile: profile, shown: Self.sectionCount)

                    ForEach(Array(profile.genres.prefix(Self.sectionCount).enumerated()), id: \.element.id) { rank, genre in
                        GenreSection(genre: genre, color: GenrePalette.color(at: rank))
                    }
                } else if !songs.isEmpty || !history.plays.isEmpty {
                    if let profile, !isLoadingGenres, profile.songCount > 0 {
                        ContentUnavailableView(
                            "No Genres Yet",
                            systemImage: "chart.pie",
                            description: Text("Apple Music hasn't tagged the songs in your library with genres.")
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                            .padding(.top, 80)
                    }
                }
            }
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Your Taste")
        // Songs and genres stream in by page, so wait for a pause before summing thousands of them.
        .task(id: songs.count &+ genres.count &* 7919 &+ history.plays.count &* 104_729) {
            if profile != nil {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled else { return }
            }
            let songs = songs, genres = genres, plays = history.plays
            profile = await Task.detached(priority: .userInitiated) {
                TasteProfile(songs: songs, genres: genres, history: plays)
            }.value
        }
        .toolbar {
            Menu {
                Button("Clear Listening History…", role: .destructive) { confirmsClear = true }
                    .disabled(history.plays.isEmpty)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
        .confirmationDialog(
            "Clear the \(history.plays.count) plays CMusic has recorded?",
            isPresented: $confirmsClear,
            titleVisibility: .visible
        ) {
            Button("Clear History", role: .destructive) { history.clear() }
        } message: {
            Text("Your Apple Music library and its play counts are not affected.")
        }
    }
}

/// Headline, the genre share bar with its legend, and a line of library statistics.
private struct TasteHeader: View {
    var profile: TasteProfile
    var shown: Int

    private var segments: [(name: String, share: Double, color: Color)] {
        var result = profile.genres.prefix(shown).enumerated().map { rank, genre in
            (name: genre.name, share: genre.share, color: GenrePalette.color(at: rank))
        }
        let rest = profile.genres.dropFirst(shown).reduce(0) { $0 + $1.share }
        if rest > 0.005 { result.append((name: "Other", share: rest, color: GenrePalette.other)) }
        return result
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(profile.headline)
                .font(.system(size: 28, weight: .bold))
                .lineLimit(2)

            ShareBar(segments: segments)

            // Identity by label as well as color, so the bar reads without the hues.
            FlowLayout(spacing: 14) {
                ForEach(segments, id: \.name) { segment in
                    HStack(spacing: 6) {
                        Circle().fill(segment.color).frame(width: 9, height: 9)
                        Text(segment.name).font(.callout.weight(.medium))
                        Text(segment.share.formatted(.percent.precision(.fractionLength(0))))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(spacing: 28) {
                Stat(value: profile.songCount.formatted(), label: "songs")
                Stat(value: profile.totalPlays.formatted(), label: "plays")
                Stat(value: profile.historyPlays.formatted(), label: "played in CMusic")
                if let decade = profile.favoriteDecade {
                    Stat(value: decade, label: "favorite decade")
                }
                Stat(value: profile.explicitShare.formatted(.percent.precision(.fractionLength(0))), label: "explicit")
                if let top = profile.topArtists.first {
                    Stat(value: top.name, label: "most played artist")
                }
            }
            .padding(.top, 4)
        }
        .padding(.horizontal, Metrics.margin)
        .padding(.top, 20)
    }
}

/// One stacked bar of genre shares, each segment separated by a sliver of background.
private struct ShareBar: View {
    var segments: [(name: String, share: Double, color: Color)]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let width = proxy.size.width - gap * CGFloat(max(segments.count - 1, 0))
            HStack(spacing: gap) {
                ForEach(segments, id: \.name) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: max(width * segment.share, 2))
                        .help("\(segment.name): \(segment.share.formatted(.percent.precision(.fractionLength(0))))")
                }
            }
        }
        .frame(height: 14)
        .clipShape(Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Genre shares")
        .accessibilityValue(segments.map { "\($0.name) \($0.share.formatted(.percent.precision(.fractionLength(0))))" }.joined(separator: ", "))
    }
}

private struct Stat: View {
    var value: String
    var label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.title3.weight(.semibold).monospacedDigit()).lineLimit(1)
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
    }
}

/// One genre: its heading and top artists, the listener's most played songs, then the genre's charts.
private struct GenreSection: View {
    var genre: GenreTaste
    var color: Color

    @Environment(MusicService.self) private var music
    @Environment(PlayerModel.self) private var player
    @State private var chart: GenreChart?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Circle().fill(color).frame(width: 12, height: 12)
                    Text(genre.name).font(.title.bold())
                    Text(genre.share.formatted(.percent.precision(.fractionLength(0))))
                        .font(.title3.monospacedDigit())
                        .foregroundStyle(.secondary)
                    TrendBadge(trend: genre.trend)
                    Spacer()
                    Button("Shuffle", systemImage: "shuffle") { player.play(genre.topSongs.shuffled()) }
                        .buttonStyle(.bordered)
                        .disabled(genre.topSongs.isEmpty)
                        .help("Shuffle your most played \(genre.name)")
                }
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .padding(.horizontal, Metrics.margin)

            SongList(title: "Your Most Played", songs: genre.topSongs) { song in
                player.play(genre.topSongs, startingAt: song)
            }

            if let chart, let chartName = chart.genreName {
                Shelf(title: "Top \(chartName) Right Now", items: chart.songs, tileWidth: Metrics.songTileWidth) { song in
                    ShelfTile(item: song) { player.play(chart.songs, startingAt: song) }
                }
                Shelf(title: "Top \(chartName) Albums", items: chart.albums) { album in
                    ShelfTile(item: album) { player.play(album) }
                }
            }
        }
        // Loaded when the section scrolls into view, so six sections don't fire twelve chart requests at once.
        .task { if chart == nil { chart = await music.genreChart(for: [genre.name] + genre.relatedGenres) } }
    }

    private var subtitle: String {
        let songs = "\(genre.songCount) song\(genre.songCount == 1 ? "" : "s")"
        let plays = "\(genre.plays.formatted()) play\(genre.plays == 1 ? "" : "s")"
        let artists = genre.topArtists.map(\.name).joined(separator: ", ")
        return artists.isEmpty ? "\(songs), \(plays)" : "\(songs), \(plays). You play \(artists) most."
    }
}

private struct TrendBadge: View {
    var trend: GenreTaste.Trend

    var body: some View {
        switch trend {
        case .rising:
            Label("Rising", systemImage: "arrow.up.right")
                .help("You've played more of this lately than usual")
        case .fading:
            Label("Fading", systemImage: "arrow.down.right")
                .help("You've played less of this lately than usual")
        case .steady:
            EmptyView()
        }
    }
}

/// Fixed hue order by genre rank, stepped separately for light and dark windows.
private enum GenrePalette {
    private static let slots: [(light: Int, dark: Int)] = [
        (0x2A78D6, 0x3987E5), // blue
        (0xEB6834, 0xD95926), // orange
        (0x1BAF7A, 0x199E70), // aqua
        (0xEDA100, 0xC98500), // yellow
        (0xE87BA4, 0xD55181), // magenta
        (0x008300, 0x008300), // green
    ]

    static func color(at rank: Int) -> Color {
        let slot = slots[rank % slots.count]
        return dynamic(light: slot.light, dark: slot.dark)
    }

    static let other = Color(nsColor: .tertiaryLabelColor)

    private static func dynamic(light: Int, dark: Int) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        })
    }
}

private extension NSColor {
    convenience init(hex: Int) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}

/// Lays children out left to right, wrapping to new lines, for the legend.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width == .infinity ? x : width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: .unspecified)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
