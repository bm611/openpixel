import AppKit
import CoreText
import ImageIO
import SwiftUI

/// Gemini-inspired neutrals with a soft blue accent. The logo keeps its brand orange.
enum Palette {
    static let brand = Color(red: 0.82, green: 0.32, blue: 0.20)

    static let background = dynamic(light: 0xFFFFFF, dark: 0x131314)
    static let surface = dynamic(light: 0xF0F4F9, dark: 0x1E1F20)
    static let surfaceHigh = dynamic(light: 0xE3E8EF, dark: 0x282A2C)
    static let surfaceHighest = dynamic(light: 0xD7DEE7, dark: 0x333537)
    static let line = dynamic(light: 0xDADCE0, dark: 0x3C4043)
    /// The moving highlight on loading placeholders.
    static let shimmer = dynamic(light: 0xFFFFFF, dark: 0x3A3C3E)

    static let text = dynamic(light: 0x1F1F1F, dark: 0xE3E3E3)
    static let textSecondary = dynamic(light: 0x444746, dark: 0xC4C7C5)
    static let textTertiary = dynamic(light: 0x747775, dark: 0x8E918F)

    static let accent = dynamic(light: 0x0B57D0, dark: 0xA8C7FA)
    static let onAccent = dynamic(light: 0xFFFFFF, dark: 0x062E6F)
    static let accentContainer = dynamic(light: 0xD3E3FD, dark: 0x1F3760)
    static let onAccentContainer = dynamic(light: 0x041E49, dark: 0xD3E3FD)

    /// Each catalog model gets its own hue so cards and glyphs are easy to tell apart.
    static func tint(for modelID: String) -> Color {
        switch modelID {
        case "z-image-turbo": hex(0x5BB974)
        case "flux2-klein-9b": hex(0xD96570)
        default: hex(0x4285F4)
        }
    }

    static func hex(_ value: UInt32) -> Color {
        Color(nsColor: nsColor(value))
    }

    private static func nsColor(_ value: UInt32) -> NSColor {
        NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? nsColor(dark) : nsColor(light)
        })
    }
}

extension Font {
    static let appFamily = "Google Sans Flex"

    /// Google Sans Flex, bundled with the app, with the system font as a fallback.
    static func app(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
        .custom(appFamily, size: size).weight(weight)
    }

    /// Faculty Glyphic, the display face from the portfolio. It has a single weight.
    static func display(_ size: CGFloat) -> Font {
        .custom("Faculty Glyphic", size: size)
    }

    /// Registers the bundled fonts for this process; safe to call more than once.
    static func registerAppFonts() {
        guard let fonts = Bundle.main.resourceURL?.appendingPathComponent("Fonts"),
              let files = try? FileManager.default.contentsOfDirectory(at: fonts, includingPropertiesForKeys: nil)
        else { return }
        for file in files where file.pathExtension == "ttf" {
            CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil)
        }
    }
}

struct PixelMark: View {
    var size: CGFloat = 32
    var tint: Color = Palette.brand
    var pixels: [Double] = [0.25, 0.7, 0, 0.7, 1, 0.65, 0, 0.65, 0.25]
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: size * 0.09), count: 3), spacing: size * 0.09) {
            ForEach(0..<9) { index in
                RoundedRectangle(cornerRadius: size * 0.035)
                    .fill(tint.opacity(pixels[index]))
                    .aspectRatio(1, contentMode: .fit)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

/// A deterministic pixel field in the spirit of the logo, used as model artwork.
struct PixelArt: View {
    let seed: String
    let tint: Color
    var cell: CGFloat = 14

    var body: some View {
        Canvas { context, size in
            var state = seed.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
                ($0 ^ UInt64($1)) &* 1_099_511_628_211
            }
            let gap = cell * 0.22
            let columns = Int(size.width / (cell + gap)) + 1
            let rows = Int(size.height / (cell + gap)) + 1
            for row in 0..<rows {
                for column in 0..<columns {
                    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
                    let noise = Double(state >> 40) / Double(1 << 24)
                    // Denser toward the right so titles on the left stay readable.
                    let weight = Double(column) / Double(max(columns - 1, 1))
                    let alpha = noise < 0.35 + weight * 0.4 ? noise * (0.25 + weight * 0.75) : 0
                    guard alpha > 0.02 else { continue }
                    let rect = CGRect(x: CGFloat(column) * (cell + gap), y: CGFloat(row) * (cell + gap),
                                      width: cell, height: cell)
                    context.fill(Path(roundedRect: rect, cornerRadius: cell * 0.18),
                                 with: .color(tint.opacity(alpha)))
                }
            }
        }
        .accessibilityHidden(true)
    }
}

/// A small tile identifying a model: the logo's 3×3 mark in the model's tint,
/// with a pattern derived from its ID so similar models stay distinguishable.
struct ModelGlyph: View {
    let modelID: String
    var size: CGFloat = 34

    private var pixels: [Double] {
        var state = modelID.utf8.reduce(UInt64(14_695_981_039_346_656_037)) {
            ($0 ^ UInt64($1)) &* 1_099_511_628_211
        }
        return (0..<9).map { index in
            if index == 4 { return 1 }
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return [0, 0.3, 0.65, 0.85][Int(state >> 62)]
        }
    }

    var body: some View {
        let tint = Palette.tint(for: modelID)
        RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
            .fill(tint.opacity(0.18))
            .overlay {
                PixelMark(size: size * 0.56, tint: tint, pixels: pixels)
            }
            .frame(width: size, height: size)
    }
}

/// A small outlined rectangle drawn at an aspect ratio's true proportions.
struct ShapeGlyph: View {
    let ratio: AspectRatio
    var size: CGFloat = 16

    var body: some View {
        let scale = size / CGFloat(max(ratio.width, ratio.height))
        RoundedRectangle(cornerRadius: 2.5)
            .strokeBorder(lineWidth: 1.4)
            .frame(width: CGFloat(ratio.width) * scale, height: CGFloat(ratio.height) * scale)
            .frame(width: size, height: size)
    }
}

struct Pill: View {
    let text: String
    var tint: Color = Palette.textSecondary

    var body: some View {
        Text(text)
            .font(.app(11, .medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(.ultraThinMaterial, in: Capsule())
            .background(tint.opacity(0.15), in: Capsule())
    }
}

/// Filled, low-contrast capsules for toolbar controls. `selected` uses the accent container.
struct ChipButtonStyle: ButtonStyle {
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        ChipBody(configuration: configuration, selected: selected)
    }

    private struct ChipBody: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.app(13, .medium))
                .foregroundStyle(selected ? Palette.onAccentContainer : Palette.text)
                .padding(.horizontal, 12).frame(height: 32)
                .background(background, in: Capsule())
                .opacity(isEnabled ? 1 : 0.45)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
        }

        private var background: Color {
            if selected { return Palette.accentContainer }
            return configuration.isPressed || hovering ? Palette.surfaceHighest : Palette.surfaceHigh
        }
    }
}

/// The primary call to action: a solid accent capsule.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Palette.accent
    var foreground: Color = Palette.onAccent

    func makeBody(configuration: Configuration) -> some View {
        PrimaryBody(configuration: configuration, tint: tint, foreground: foreground)
    }

    private struct PrimaryBody: View {
        let configuration: Configuration
        let tint: Color
        let foreground: Color
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.app(14, .medium))
                .foregroundStyle(isEnabled ? foreground : Palette.textTertiary)
                .padding(.horizontal, 18).frame(height: 38)
                .background(isEnabled ? tint : Palette.surfaceHigh, in: Capsule())
                .brightness(isEnabled && hovering ? 0.05 : 0)
                .scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

/// Plain icon buttons with a circular hover background.
struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconBody(configuration: configuration)
    }

    private struct IconBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.app(14, .medium))
                .frame(minWidth: 32, minHeight: 32)
                .padding(.horizontal, 2)
                .background(configuration.isPressed ? Palette.surfaceHighest : hovering ? Palette.surfaceHigh : .clear,
                            in: Capsule())
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Capsule())
                .onHover { hovering = $0 }
        }
    }
}

/// Rows inside popovers and menus: full width, rounded hover highlight.
struct RowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        RowBody(configuration: configuration)
    }

    private struct RowBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.app(13))
                .foregroundStyle(Palette.text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(configuration.isPressed ? Palette.surfaceHighest : hovering ? Palette.surfaceHigh : .clear,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

/// Decodes library images once; thumbnails are downsampled to keep grids light.
enum ImageCache {
    private static let full = NSCache<NSURL, NSImage>()
    private static let thumbnails = NSCache<NSURL, NSImage>()

    static func image(at url: URL) -> NSImage? {
        if let cached = full.object(forKey: url as NSURL) { return cached }
        guard let image = NSImage(contentsOf: url) else { return nil }
        full.setObject(image, forKey: url as NSURL)
        return image
    }

    static func thumbnail(at url: URL, pixels: Int = 320) -> NSImage? {
        if let cached = thumbnails.object(forKey: url as NSURL) { return cached }
        let options = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixels
        ] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else { return nil }
        let image = NSImage(cgImage: cgImage, size: .zero)
        thumbnails.setObject(image, forKey: url as NSURL)
        return image
    }
}
