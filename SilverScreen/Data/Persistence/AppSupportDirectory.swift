//
//  AppSupportDirectory.swift
//  SilverScreen
//
//  On-device library data lives under Application Support/SilverScreen.
//  library.sqlite is the source of truth; legacy *.json files are imported once.
//

import Foundation

enum AppSupportDirectory {
    static func fileURL(fileName: String) throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("SilverScreen", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
