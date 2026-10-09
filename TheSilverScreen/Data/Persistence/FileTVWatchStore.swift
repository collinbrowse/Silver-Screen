//
//  FileTVWatchStore.swift
//  TheSilverScreen
//
//  Versioned tv-progress.json. One bad series record is skipped. A file that
//  cannot be read at all is moved aside.
//

import Foundation

private struct TVWatchFile: Codable {
    static let currentVersion = 1
    var version: Int
    var series: [TVSeriesWatchState]
}

actor FileTVWatchStore: TVWatchStore {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(fileURL: URL) {
        self.fileURL = fileURL
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    static func applicationSupportURL(fileName: String = "tv-progress.json") throws -> URL {
        try AppSupportDirectory.fileURL(fileName: fileName)
    }

    func load() async throws -> [TVSeriesWatchState] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = object["series"] as? [Any] else {
            quarantineCorruptFile()
            return []
        }

        var salvaged: [TVSeriesWatchState] = []
        var changed = false
        for element in elements {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let decoded = try? decoder.decode(TVSeriesWatchState.self, from: elementData) else {
                changed = true
                continue
            }
            salvaged.append(decoded)
        }

        if changed {
            try await save(salvaged)
        }
        return salvaged
    }

    func save(_ states: [TVSeriesWatchState]) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = TVWatchFile(version: TVWatchFile.currentVersion, series: states)
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
    }

    private func quarantineCorruptFile() {
        let destination = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }
}
