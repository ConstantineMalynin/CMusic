//
//  TileShadow.swift
//  CMusic
//

import AppKit
import SwiftUI

/// A drop shadow for a rounded square, drawn from one cached bitmap stretched nine-slice style.
///
/// SwiftUI's `.shadow` renders every tile through its own offscreen pass, which dominates frame time
/// once a grid shows dozens of tiles. A stretched bitmap is a single textured quad per tile.
struct TileShadow: View {
    var cornerRadius: CGFloat
    var radius: CGFloat
    var opacity: Double = 0.15

    var body: some View {
        let margin = Self.margin(for: radius)
        let inset = margin + cornerRadius
        Image(decorative: Self.bitmap(cornerRadius: cornerRadius, radius: radius, opacity: opacity), scale: Self.scale)
            .resizable(
                capInsets: EdgeInsets(top: inset, leading: inset, bottom: inset, trailing: inset),
                resizingMode: .stretch
            )
            .padding(-margin)
    }

    private static let scale: CGFloat = 2
    @MainActor private static var cache: [String: CGImage] = [:]

    /// Room around the shape for the blur and the downward offset.
    private static func margin(for radius: CGFloat) -> CGFloat { radius * 3 }

    @MainActor
    private static func bitmap(cornerRadius: CGFloat, radius: CGFloat, opacity: Double) -> CGImage {
        let key = "\(cornerRadius)/\(radius)/\(opacity)"
        if let image = cache[key] { return image }

        let margin = margin(for: radius)
        let core = cornerRadius * 2 + 2 // 2pt of stretchable middle
        let size = core + margin * 2
        let context = CGContext(
            data: nil,
            width: Int(size * scale),
            height: Int(size * scale),
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.scaleBy(x: scale, y: scale)

        let path = CGPath(
            roundedRect: CGRect(x: margin, y: margin, width: core, height: core),
            cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil
        )
        context.setShadow(offset: CGSize(width: 0, height: -radius / 2), blur: radius * 2, color: CGColor(gray: 0, alpha: opacity))
        context.setFillColor(.black)
        context.addPath(path)
        context.fillPath()

        // Punch the shape itself out, leaving only the shadow around it.
        context.setShadow(offset: .zero, blur: 0, color: nil)
        context.setBlendMode(.clear)
        context.addPath(path)
        context.fillPath()

        let image = context.makeImage()!
        cache[key] = image
        return image
    }
}
