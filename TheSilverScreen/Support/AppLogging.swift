//
//  AppLogging.swift
//  TheSilverScreen
//

import Foundation
import os

enum LogCategory: String, Sendable {
    case networking
    case persistence
    case ui
    case navigation
}

protocol AppLogging: Sendable {
    func debug(_ message: String, category: LogCategory)
    func error(_ message: String, category: LogCategory)
}

struct OSAppLogger: AppLogging {
    private let subsystem = "com.collinbrowse.thesilverscreen"

    func debug(_ message: String, category: LogCategory) {
        logger(for: category).debug("\(message, privacy: .public)")
    }

    func error(_ message: String, category: LogCategory) {
        logger(for: category).error("\(message, privacy: .public)")
    }

    private func logger(for category: LogCategory) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
