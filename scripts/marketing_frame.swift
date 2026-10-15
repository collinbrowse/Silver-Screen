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

/// One image to write. Sizes are pixels. `kind` is `screenshot` (one `input`) or
/// `banner` (several `inputs`, fanned out with the first in the middle).
struct Job: Decodable {
    let kind: String?
    let input: String?
    let inputs: [String]?
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

    var body: some View {
        let reach = max(size.width, size.height)
        ZStack {
            if isDark {
                LinearGradient(colors: [Palette.tealMid, Palette.tealDeep], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [Palette.accent.opacity(0.22), .clear],
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

/// Product page header (21:9) or search results art (3:2): one short phrase over
/// a fan of phones. Apple crops these differently per device and publishes no safe
/// area, so the phrase and the middle phone stay in the center third; the outer
/// phones are decoration that may be cropped away.
struct BannerArt: View {
    let job: Job
    let screenshots: [NSImage]

    private var isDark: Bool { job.appearance == "dark" }

    var body: some View {
        let unit = job.height / 1646
        let isWide = job.width / job.height > 2
        let phoneWidth = (isWide ? 560 : 640) * unit
        let textHeight = (isWide ? 300 : 380) * unit
        // Middle phone first, then alternating left and right, farther out each pair.
        let slots: [(x: Double, scale: Double, angle: Double, dim: Double)] = [
            (0, 1, 0, 0),
            (-1, 0.86, -6, 0.15),
            (1, 0.86, 6, 0.15),
            (-2, 0.74, -11, 0.3),
            (2, 0.74, 11, 0.3),
        ]
        let spacing = phoneWidth * (isWide ? 1.08 : 1.06)

        ZStack(alignment: .top) {
            BrandBackground(isDark: isDark, size: CGSize(width: job.width, height: job.height))

            ForEach(Array(zip(screenshots, slots).enumerated().reversed()), id: \.offset) { _, pair in
                let (image, slot) = pair
                PhoneFrame(
                    screenshot: image,
                    screenWidth: phoneWidth,
                    corner: phoneWidth * 0.14,
                    bezel: 9 * unit,
                    unit: unit * 0.5,
                    isDark: isDark
                )
                .overlay(Color.black.opacity(slot.dim).clipShape(RoundedRectangle(cornerRadius: phoneWidth * 0.15, style: .continuous)))
                .scaleEffect(slot.scale, anchor: .top)
                .rotationEffect(.degrees(slot.angle), anchor: .top)
                .offset(x: slot.x * spacing, y: textHeight + abs(slot.x) * 70 * unit)
            }

            VStack(spacing: 18 * unit) {
                Text(job.caption)
                    .font(.system(size: (isWide ? 116 : 140) * unit, weight: .bold))
                    .tracking(-2 * unit)
                    .foregroundStyle(isDark ? Color.white : Palette.tealDeep)
                if let subcaption = job.subcaption, !subcaption.isEmpty {
                    Text(subcaption)
                        .font(.system(size: (isWide ? 52 : 62) * unit, weight: .medium))
                        .foregroundStyle(isDark ? Color.white.opacity(0.72) : Palette.teal)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.top, (isWide ? 100 : 130) * unit)
        }
        .frame(width: job.width, height: job.height, alignment: .top)
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
    let paths = job.inputs ?? [job.input].compactMap { $0 }
    let images = try paths.map { path in
        guard let image = NSImage(contentsOfFile: path) else {
            throw NSError(domain: "frame", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable \(path)"])
        }
        return image
    }
    let content: AnyView = job.kind == "banner"
        ? AnyView(BannerArt(job: job, screenshots: images))
        : AnyView(FramedShot(job: job, screenshot: images[0]))
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
