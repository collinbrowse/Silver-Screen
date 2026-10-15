//
//  marketing_frame.swift
//  SilverScreen
//
//  Puts raw simulator screenshots on a captioned background at exact App Store
//  pixel sizes: framed screenshots (`marketing.py frame`) and the product page
//  header and search results art (`marketing.py header`). The script writes the
//  job list:
//
//    swift scripts/marketing_frame.swift jobs.json
//
//  macOS only. SwiftUI's ImageRenderer draws everything, so there are no packages
//  and no downloaded device bezels.
//

import AppKit
import SwiftUI

/// One image to write. Sizes are pixels. `kind` is `screenshot` (default, one
/// `input`), `header` (no input), or `search` (one `input`, the phone shown).
struct Job: Decodable {
    let kind: String?
    let input: String?
    let output: String
    let caption: String
    let subcaption: String?
    let width: Double
    let height: Double
    let device: String
    let appearance: String
}

/// Brand colors from the app icon's teal film strip and the in-app accent.
enum Palette {
    static let tealDeep = Color(red: 0.05, green: 0.17, blue: 0.22)
    static let tealMid = Color(red: 0.11, green: 0.33, blue: 0.40)
    static let teal = Color(red: 0.18, green: 0.45, blue: 0.53)
    static let silver = Color(red: 0.95, green: 0.96, blue: 0.97)
    static let mist = Color(red: 0.86, green: 0.91, blue: 0.93)
    static let accent = Color(red: 0.98, green: 0.51, blue: 0.08)
}

/// The full App Store image: caption on top, the screenshot in a slim device
/// outline below, running off the bottom edge.
struct FramedShot: View {
    let job: Job
    let screenshot: NSImage

    private var isDark: Bool { job.appearance == "dark" }
    private var isPad: Bool { job.device == "ipad" }
    private var unit: Double { job.width / 1320 }

    var body: some View {
        let screenWidth = job.width * (isPad ? 0.78 : 0.765)
        let bezel = (isPad ? 22 : 20) * unit
        // Display corner radius as a share of screen width (iPhone 17 Pro Max, iPad Pro 13").
        let corner = screenWidth * (isPad ? 0.022 : 0.14)

        ZStack(alignment: .top) {
            BrandBackground(isDark: isDark, size: CGSize(width: job.width, height: job.height))
            VStack(spacing: 0) {
                VStack(spacing: 26 * unit) {
                    Text(job.caption)
                        .font(.system(size: (isPad ? 84 : 104) * unit, weight: .bold))
                        .tracking(-1.5 * unit)
                        .foregroundStyle(isDark ? Color.white : Palette.tealDeep)
                    if let subcaption = job.subcaption, !subcaption.isEmpty {
                        Text(subcaption)
                            .font(.system(size: (isPad ? 42 : 50) * unit, weight: .medium))
                            .foregroundStyle(isDark ? Color.white.opacity(0.72) : Palette.teal)
                    }
                }
                .multilineTextAlignment(.center)
                .lineSpacing(4 * unit)
                .frame(width: job.width * 0.86)
                .padding(.top, (isPad ? 150 : 190) * unit)
                .frame(height: (isPad ? 540 : 600) * unit, alignment: .top)

                PhoneFrame(
                    screenshot: screenshot,
                    screenWidth: screenWidth,
                    corner: corner,
                    bezel: bezel,
                    unit: unit,
                    isDark: isDark
                )
            }
        }
        .frame(width: job.width, height: job.height, alignment: .top)
        .clipped()
    }
}

/// A screenshot in a slim device outline with a soft shadow.
struct PhoneFrame: View {
    let screenshot: NSImage
    let screenWidth: Double
    let corner: Double
    let bezel: Double
    let unit: Double
    let isDark: Bool

    var body: some View {
        let aspect = screenshot.size.height / max(screenshot.size.width, 1)
        Image(nsImage: screenshot)
            .resizable()
            .interpolation(.high)
            .frame(width: screenWidth, height: screenWidth * aspect)
            .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
            .padding(bezel)
            .background(
                RoundedRectangle(cornerRadius: corner + bezel, style: .continuous)
                    .fill(Color(white: 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: corner + bezel, style: .continuous)
                    .strokeBorder(Color.white.opacity(isDark ? 0.22 : 0.5), lineWidth: 3 * unit)
            )
            .shadow(color: .black.opacity(isDark ? 0.55 : 0.28), radius: 60 * unit, y: 30 * unit)
    }
}

/// Teal gradient with a warm glow (dark) or silver with a teal glow (light).
struct BrandBackground: View {
    let isDark: Bool
    let size: CGSize
    /// Warm orange glow on dark screenshots; the header art uses a cool teal glow,
    /// since orange over a large teal field turns muddy.
    var warmGlow = true

    var body: some View {
        let reach = max(size.width, size.height)
        ZStack {
            if isDark {
                LinearGradient(colors: [Palette.tealMid, Palette.tealDeep], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [(warmGlow ? Palette.accent.opacity(0.22) : Palette.teal.opacity(0.45)), .clear],
                    center: .init(x: 0.5, y: 0.55),
                    startRadius: 0,
                    endRadius: reach * 0.75
                )
            } else {
                LinearGradient(colors: [Palette.silver, Palette.mist], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [Palette.teal.opacity(0.16), .clear],
                    center: .init(x: 0.5, y: 0.6),
                    startRadius: 0,
                    endRadius: reach * 0.8
                )
            }
        }
    }
}

/// The app icon's motif: a film strip winding across the canvas, with frames down
/// the middle and sprocket holes along both edges. Drawn, so it scales to any size.
struct FilmStrip: View {
    /// Center line height (share of canvas height) at mid-width.
    let base: Double
    /// Rise from left to right edge, as a share of height (negative climbs to the right).
    let tilt: Double
    /// Wave height and number of waves across the width.
    let amplitude: Double
    let cycles: Double
    let phase: Double
    /// Band thickness as a share of canvas height.
    let thickness: Double
    let isDark: Bool

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let band = size.height * thickness
            let points = curve(in: size)
            let film = isDark ? Color(red: 0.72, green: 0.80, blue: 0.83) : Palette.teal
            let frame = isDark ? Color(red: 0.60, green: 0.69, blue: 0.73) : Color(red: 0.24, green: 0.53, blue: 0.62)
            let hole = isDark ? Palette.tealDeep : Palette.silver

            ZStack {
                Self.path(points)
                    .stroke(film, style: StrokeStyle(lineWidth: band, lineCap: .butt, lineJoin: .round))
                    .shadow(color: .black.opacity(isDark ? 0.45 : 0.18), radius: band * 0.25, y: band * 0.12)
                Self.path(points)
                    .stroke(frame, style: StrokeStyle(lineWidth: band * 0.56, lineCap: .butt, dash: [band * 0.78, band * 0.1]))
                ForEach([-1.0, 1.0], id: \.self) { side in
                    Self.path(Self.offset(points, by: side * band * 0.39))
                        .stroke(hole, style: StrokeStyle(lineWidth: band * 0.1, lineCap: .butt, dash: [band * 0.1, band * 0.1]))
                }
            }
        }
    }

    /// Sampled densely so the sprocket rows can follow the curve's normal.
    private func curve(in size: CGSize) -> [CGPoint] {
        let margin = size.width * 0.08
        let steps = 400
        return (0...steps).map { index in
            let t = Double(index) / Double(steps)
            let share = base + tilt * (t - 0.5) + amplitude * sin(2 * .pi * (cycles * t + phase))
            return CGPoint(x: -margin + t * (size.width + 2 * margin), y: share * size.height)
        }
    }

    static func offset(_ points: [CGPoint], by distance: Double) -> [CGPoint] {
        points.indices.map { index in
            let previous = points[max(index - 1, 0)]
            let next = points[min(index + 1, points.count - 1)]
            let dx = next.x - previous.x
            let dy = next.y - previous.y
            let length = max(sqrt(dx * dx + dy * dy), 0.0001)
            return CGPoint(x: points[index].x - dy / length * distance, y: points[index].y + dx / length * distance)
        }
    }

    static func path(_ points: [CGPoint]) -> Path {
        Path { path in
            path.addLines(points)
        }
    }
}

/// Product page header (21:9): brand art and a wordmark, no app UI, like Apple's
/// examples. iPhone shows roughly the middle 60% under the back and share buttons,
/// so the wordmark is centered and the strip's busy parts stay to the sides.
struct HeaderArt: View {
    let job: Job

    private var isDark: Bool { job.appearance == "dark" }

    var body: some View {
        let unit = job.height / 1646
        ZStack {
            BrandBackground(isDark: isDark, size: CGSize(width: job.width, height: job.height), warmGlow: false)
            FilmStrip(base: 0.76, tilt: -0.08, amplitude: 0.07, cycles: 1.3, phase: 0.05, thickness: 0.14, isDark: isDark)
            VStack(spacing: 30 * unit) {
                Text(job.caption.uppercased())
                    .font(.system(size: 230 * unit, weight: .semibold).width(.expanded))
                    .tracking(18 * unit)
                    .foregroundStyle(isDark ? Color.white : Palette.tealDeep)
                    .shadow(color: .black.opacity(isDark ? 0.35 : 0.08), radius: 30 * unit)
                if let subcaption = job.subcaption, !subcaption.isEmpty {
                    Text(subcaption)
                        .font(.system(size: 64 * unit, weight: .medium))
                        .foregroundStyle(isDark ? Color.white.opacity(0.75) : Palette.teal)
                }
            }
            .offset(y: -200 * unit)
        }
        .frame(width: job.width, height: job.height)
        .clipped()
    }
}

/// Search results art (3:2): one phrase on the left and one phone on the right,
/// like Apple's Forest Explorer and Airline examples.
struct SearchArt: View {
    let job: Job
    let screenshot: NSImage

    private var isDark: Bool { job.appearance == "dark" }

    var body: some View {
        let unit = job.height / 2560
        let phoneWidth = 1040 * unit
        ZStack(alignment: .topLeading) {
            BrandBackground(isDark: isDark, size: CGSize(width: job.width, height: job.height), warmGlow: false)
            FilmStrip(base: 0.74, tilt: -0.72, amplitude: 0.04, cycles: 1, phase: 0, thickness: 0.15, isDark: isDark)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 56 * unit) {
                Text(job.caption.replacingOccurrences(of: ". ", with: ".\n"))
                    .font(.system(size: 250 * unit, weight: .bold))
                    .tracking(-4 * unit)
                    .lineSpacing(-10 * unit)
                    .foregroundStyle(isDark ? Color.white : Palette.tealDeep)
                if let subcaption = job.subcaption, !subcaption.isEmpty {
                    Text(subcaption)
                        .font(.system(size: 84 * unit, weight: .medium))
                        .foregroundStyle(isDark ? Color.white.opacity(0.75) : Palette.teal)
                        .frame(width: 1600 * unit, alignment: .leading)
                }
            }
            .padding(.leading, 300 * unit)
            .padding(.top, 520 * unit)

            PhoneFrame(
                screenshot: screenshot,
                screenWidth: phoneWidth,
                corner: phoneWidth * 0.14,
                bezel: 18 * unit,
                unit: unit,
                isDark: isDark
            )
            .offset(x: job.width - phoneWidth - 520 * unit, y: 300 * unit)
        }
        .frame(width: job.width, height: job.height, alignment: .topLeading)
        .clipped()
    }
}

/// The same pixels without an alpha channel. App Store Connect rejects header and
/// search art with one, and has rejected screenshots with one before.
func opaque(_ image: CGImage) -> CGImage? {
    guard let context = CGContext(
        data: nil,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else {
        return nil
    }
    context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    return context.makeImage()
}

@MainActor
func render(_ job: Job) throws {
    let images = try [job.input].compactMap { $0 }.map { path in
        guard let image = NSImage(contentsOfFile: path) else {
            throw NSError(domain: "frame", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable \(path)"])
        }
        return image
    }
    let content: AnyView
    switch job.kind {
        case "header":
            content = AnyView(HeaderArt(job: job))
        case "search":
            content = AnyView(SearchArt(job: job, screenshot: images[0]))
        default:
            content = AnyView(FramedShot(job: job, screenshot: images[0]))
    }
    let renderer = ImageRenderer(content: content)
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: job.width, height: job.height)
    guard
        let cgImage = renderer.cgImage.flatMap(opaque),
        let png = NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "frame", code: 2, userInfo: [NSLocalizedDescriptionKey: "Render failed for \(job.output)"])
    }
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: job.output).deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try png.write(to: URL(fileURLWithPath: job.output))
    print("framed \(job.output) (\(cgImage.width)x\(cgImage.height))")
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift marketing_frame.swift jobs.json\n".utf8))
    exit(2)
}
do {
    let jobs = try JSONDecoder().decode([Job].self, from: Data(contentsOf: URL(fileURLWithPath: arguments[1])))
    try MainActor.assumeIsolated {
        for job in jobs {
            try render(job)
        }
    }
} catch {
    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8))
    exit(1)
}
