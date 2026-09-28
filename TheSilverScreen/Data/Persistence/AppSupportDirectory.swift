//
//  AppSupportDirectory.swift
//  TheSilverScreen
//
//  On-device JSON lives in Application Support. Each store names its own file.
//  favorites.json is never opened; lists.json is a separate library.
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
        let directory = base.appendingPathComponent("TheSilverScreen", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName, isDirectory: false)
    }
}
