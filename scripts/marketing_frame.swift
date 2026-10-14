//
//  marketing_frame.swift
//  SilverScreen
//
//  Puts raw simulator screenshots on a captioned background at exact App Store
//  pixel sizes. Run by `scripts/marketing.py frame`, which writes the job list:
//
//    swift scripts/marketing_frame.swift jobs.json
//
//  macOS only. SwiftUI's ImageRenderer draws everything, so there are no packages
//  and no downloaded device bezels.
//

import AppKit
import SwiftUI

/// One framed image to write. Sizes are pixels.
struct Job: Decodable {
    let input: String
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
        let aspect = screenshot.size.height / max(screenshot.size.width, 1)
        let screenHeight = screenWidth * aspect
        let bezel = (isPad ? 22 : 20) * unit
        // Display corner radius as a share of screen width (iPhone 17 Pro Max, iPad Pro 13").
        let corner = screenWidth * (isPad ? 0.022 : 0.14)

        ZStack(alignment: .top) {
            background
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

                Image(nsImage: screenshot)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: screenWidth, height: screenHeight)
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
        .frame(width: job.width, height: job.height, alignment: .top)
        .clipped()
    }

    @ViewBuilder
    private var background: some View {
        if isDark {
            ZStack {
                LinearGradient(colors: [Palette.tealMid, Palette.tealDeep], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [Palette.accent.opacity(0.22), .clear],
                    center: .init(x: 0.5, y: 0.55),
                    startRadius: 0,
                    endRadius: job.width * 0.75
                )
            }
        } else {
            ZStack {
                LinearGradient(colors: [Palette.silver, Palette.mist], startPoint: .top, endPoint: .bottom)
                RadialGradient(
                    colors: [Palette.teal.opacity(0.16), .clear],
                    center: .init(x: 0.5, y: 0.6),
                    startRadius: 0,
                    endRadius: job.width * 0.8
                )
            }
        }
    }
}

@MainActor
func render(_ job: Job) throws {
    guard let screenshot = NSImage(contentsOfFile: job.input) else {
        throw NSError(domain: "frame", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unreadable \(job.input)"])
    }
    let renderer = ImageRenderer(content: FramedShot(job: job, screenshot: screenshot))
    renderer.scale = 1
    renderer.proposedSize = ProposedViewSize(width: job.width, height: job.height)
    guard
        let cgImage = renderer.cgImage,
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
