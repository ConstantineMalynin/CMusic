//
//  ArtworkView.swift
//  CMusic
//

import MusicKit
import SwiftUI

/// Square (or circular) MusicKit artwork with a neutral placeholder.
struct ArtworkView: View {
    var artwork: Artwork?
    var cornerRadius: CGFloat = 6
    var isCircle = false
    /// Drawn from a cached bitmap rather than the image, which is much cheaper to render while scrolling.
    var shadowRadius: CGFloat = 0
    /// The square's side when the caller knows it. Otherwise it is measured, which costs a second layout pass.
    var side: CGFloat? = nil

    @State private var measuredSide: CGFloat = 0

    var body: some View {
        let side = self.side ?? measuredSide
        let shape = isCircle
            ? AnyShape(Circle())
            : AnyShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))

        square
            .overlay {
                if let artwork {
                    if side > 0 {
                        LoadedArtwork(artwork: artwork, side: side)
                    }
                } else {
                    Image(systemName: "music.note")
                        .font(.system(size: max(side * 0.35, 1)))
                        .foregroundStyle(.tertiary)
                }
            }
            .clipShape(shape)
            .overlay(shape.stroke(.primary.opacity(0.08), lineWidth: 0.5))
            .background {
                if shadowRadius > 0 {
                    if isCircle {
                        shape.fill(.background)
                            .shadow(color: .black.opacity(0.15), radius: shadowRadius, y: shadowRadius / 2)
                    } else {
                        TileShadow(cornerRadius: cornerRadius, radius: shadowRadius)
                    }
                }
            }
    }

    @ViewBuilder
    private var square: some View {
        let fill = Rectangle().fill(.quaternary)
        if let side {
            fill.frame(width: side, height: side)
        } else {
            fill.aspectRatio(1, contentMode: .fit)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredSide = $0 }
        }
    }
}

/// Shows cached artwork immediately, otherwise loads it through `ArtworkLoader` and fades it in.
private struct LoadedArtwork: View {
    var artwork: Artwork
    var side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: CGImage?

    var body: some View {
        let pixelSize = ArtworkLoader.pixelSize(forPoints: side, scale: displayScale)
        if let url = ArtworkLoader.url(for: artwork, pixelSize: pixelSize) {
            let loader = ArtworkLoader.shared
            let shown = image ?? loader.cachedImage(for: artwork, pixelSize: pixelSize)
            ZStack {
                if let shown {
                    Image(decorative: shown, scale: displayScale)
                        .resizable()
                        .scaledToFill()
                        .transition(.opacity)
                }
            }
            .frame(width: side, height: side)
            .task(id: url) {
                // Keep showing the previous image until the new size arrives, so resizing never flashes.
                guard loader.cachedImage(for: artwork, pixelSize: pixelSize) == nil else { return }
                let loaded = await loader.image(for: artwork, pixelSize: pixelSize)
                guard !Task.isCancelled, let loaded else { return }
                withAnimation(.easeOut(duration: 0.2)) { image = loaded }
            }
        } else {
            ArtworkImage(artwork, width: side, height: side)
        }
    }
}
