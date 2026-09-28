//
//  FileListsStore.swift
//  TheSilverScreen
//
//  Versioned lists.json. One bad list or entry is skipped. A file that cannot
//  be read at all is moved aside. favorites.json is a different file and is ignored.
//

import Foundation

private struct ListsFile: Codable {
    static let currentVersion = 1
    var version: Int
    var lists: [LibraryList]
    var entries: [ListEntry]
}

actor FileListsStore: ListsStore {
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

    static func applicationSupportURL(fileName: String = "lists.json") throws -> URL {
        try AppSupportDirectory.fileURL(fileName: fileName)
    }

    func load() async throws -> LibrarySnapshot {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return .empty
        }
        let data = try Data(contentsOf: fileURL)
        if data.isEmpty {
            return .empty
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            quarantineCorruptFile()
            return .empty
        }
        guard object["lists"] != nil || object["entries"] != nil else {
            quarantineCorruptFile()
            return .empty
        }

        let lists = decodeArray(object["lists"], as: LibraryList.self)
        let entries = decodeArray(object["entries"], as: ListEntry.self)
        return LibrarySnapshot(lists: lists, entries: entries)
    }

    func save(_ snapshot: LibrarySnapshot) async throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let file = ListsFile(
            version: ListsFile.currentVersion,
            lists: snapshot.lists,
            entries: snapshot.entries
        )
        let data = try encoder.encode(file)
        try data.write(to: fileURL, options: .atomic)
    }

    private func decodeArray<T: Decodable>(_ value: Any?, as type: T.Type) -> [T] {
        guard let elements = value as? [Any] else { return [] }
        return elements.compactMap { element in
            guard JSONSerialization.isValidJSONObject(element),
                  let elementData = try? JSONSerialization.data(withJSONObject: element) else {
                return nil
            }
            return try? decoder.decode(T.self, from: elementData)
        }
    }

    private func quarantineCorruptFile() {
        let destination = fileURL.appendingPathExtension("corrupt")
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: fileURL, to: destination)
    }
}
