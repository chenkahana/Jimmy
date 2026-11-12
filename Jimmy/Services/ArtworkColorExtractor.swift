import SwiftUI
import UIKit

@MainActor
final class ArtworkColorExtractor: ObservableObject {
    static let shared = ArtworkColorExtractor()

    @Published var dominantColor: Color = .accentColor
    @Published var vibrantColor: Color = .accentColor
    @Published var mutedColor: Color = .gray

    private var cache: [String: CachedColors] = [:]
    private let maxCacheSize = 30

    private nonisolated struct CachedColors: Sendable {
        let dominant: Color
        let vibrant: Color
        let muted: Color
    }

    private init() {}

    func extractColors(from url: URL?) {
        guard let url = url else { return }

        let key = url.absoluteString

        if let cached = cache[key] {
            withAnimation(.easeInOut(duration: 0.6)) {
                dominantColor = cached.dominant
                vibrantColor = cached.vibrant
                mutedColor = cached.muted
            }
            return
        }

        Task(priority: .userInitiated) { [weak self] in
            guard let colors = await Self.extractColorsFromImage(url: url) else { return }
            self?.applyColors(colors, forKey: key)
        }
    }

    /// The artwork's most common color, without changing the shared colors Now Playing shows.
    static func dominantColor(of url: URL) async -> Color? {
        await extractColorsFromImage(url: url)?.dominant
    }

    private func applyColors(_ colors: CachedColors, forKey key: String) {
        if cache.count >= maxCacheSize {
            cache.removeValue(forKey: cache.keys.first ?? "")
        }
        cache[key] = colors

        withAnimation(.easeInOut(duration: 0.6)) {
            dominantColor = colors.dominant
            vibrantColor = colors.vibrant
            mutedColor = colors.muted
        }
    }

    /// Downloads and samples the artwork off the main actor.
    @concurrent
    private nonisolated static func extractColorsFromImage(url: URL) async -> CachedColors? {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let image = UIImage(data: data),
                  let cgImage = image.cgImage else { return nil }

            let size = 40
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            var pixelData = [UInt8](repeating: 0, count: size * size * 4)

            guard let context = CGContext(
                data: &pixelData,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: size * 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }

            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: size, height: size))

            var colorCounts: [UInt32: Int] = [:]
            var maxSaturation: (h: CGFloat, s: CGFloat, b: CGFloat) = (0, 0, 0)
            var totalH: CGFloat = 0
            var totalS: CGFloat = 0
            var totalB: CGFloat = 0
            var pixelCount: CGFloat = 0

            for i in stride(from: 0, to: pixelData.count, by: 4) {
                let r = pixelData[i]
                let g = pixelData[i + 1]
                let b = pixelData[i + 2]

                let quantR = r / 32
                let quantG = g / 32
                let quantB = b / 32
                let key = UInt32(quantR) << 16 | UInt32(quantG) << 8 | UInt32(quantB)
                colorCounts[key, default: 0] += 1

                let uiColor = UIColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
                var h: CGFloat = 0, s: CGFloat = 0, br: CGFloat = 0
                uiColor.getHue(&h, saturation: &s, brightness: &br, alpha: nil)

                if s > maxSaturation.s {
                    maxSaturation = (h, s, br)
                }

                totalH += h
                totalS += s
                totalB += br
                pixelCount += 1
            }

            guard pixelCount > 0 else { return nil }

            let dominantKey = colorCounts.max(by: { $0.value < $1.value })?.key ?? 0
            let dR = CGFloat((dominantKey >> 16) & 0xFF) * 32 / 255
            let dG = CGFloat((dominantKey >> 8) & 0xFF) * 32 / 255
            let dB = CGFloat(dominantKey & 0xFF) * 32 / 255

            return CachedColors(
                dominant: Color(red: dR, green: dG, blue: dB),
                vibrant: Color(hue: maxSaturation.h, saturation: min(maxSaturation.s * 1.2, 1.0), brightness: min(maxSaturation.b * 1.1, 1.0)),
                muted: Color(hue: totalH / pixelCount, saturation: (totalS / pixelCount) * 0.5, brightness: (totalB / pixelCount) * 0.8)
            )
        } catch {
            return nil
        }
    }
}
