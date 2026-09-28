//
//  FileAnnotationsStore.swift
//  TheSilverScreen
//
//  Versioned JSON file for personal scores and notes. A damaged file keeps every
//  record that still decodes and is rewritten clean. The file is moved aside only
//  when nothing in it can be read.
//

import Foundation

private struct AnnotationsFile: Codable {
    static let currentVersion = 1
    var version: Int
    var records: [MediaAnnotation]
}

actor FileAnnotationsStore: AnnotationsStore {
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

    static func applicationSupportURL(fileName: String = "annotations.json") throws -> URL {
        try AppSupportDirectory.fileURL(fileName: fileName)
    }

    func load() async throws -> [MediaAnnotation] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return []
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let elements = object["records"] as? [Any] else {
            quarantineCorruptFile()
            return []
        }

        var salvaged: [MediaAnnotation] = []
        var changed = false
        for element in elements {
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element),
                  let decoded = try? decoder.decode(MediaAnnotation.self, from: elementData),
                  let normalized = decoded.normalized() else {
                changed = true
                continue
            }
            if normalized != decoded {
                changed = true
            }
            salvaged.append(normalized)
        }

        if changed {
            try await save(salvaged)
        }
        return salvaged
    }

    func save(_ records: [MediaAnnotation]) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = AnnotationsFile(version: AnnotationsFile.currentVersion, records: records)
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
    }

    private func quarantineCorruptFile() {
        let destination = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }
}
