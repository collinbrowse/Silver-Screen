//
//  SQLiteDatabase.swift
//  SilverScreen
//
//  Thin wrapper over the system SQLite3 C API. Owned exclusively by
//  SQLiteLibraryStore (an actor); not shared across concurrency domains.
//

import Foundation
import SQLite3

/// Failures from open, prepare, or step. Mapped to `AppError.persistence` at the repository.
enum SQLiteDatabaseError: Error, Equatable {
    case openFailed(code: Int32)
    case prepareFailed(message: String)
    case stepFailed(message: String)
    case executionFailed(message: String)
}

final class SQLiteDatabase {
    private var db: OpaquePointer?

    init(fileURL: URL) throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var handle: OpaquePointer?
        let flags = SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX
        let code = sqlite3_open_v2(fileURL.path, &handle, flags, nil)
        guard code == SQLITE_OK, let handle else {
            if let handle {
                sqlite3_close(handle)
            }
            throw SQLiteDatabaseError.openFailed(code: code)
        }
        db = handle
        try execute("PRAGMA journal_mode = WAL;")
        try execute("PRAGMA foreign_keys = ON;")
    }

    deinit {
        close()
    }

    /// Releases the connection. Safe to call more than once; `deinit` also calls this.
    func close() {
        if let db {
            sqlite3_close(db)
            self.db = nil
        }
    }

    func execute(_ sql: String) throws {
        guard let db else { throw SQLiteDatabaseError.openFailed(code: SQLITE_MISUSE) }
        var errorMessage: UnsafeMutablePointer<CChar>?
        let code = sqlite3_exec(db, sql, nil, nil, &errorMessage)
        if code != SQLITE_OK {
            let message = errorMessage.map { String(cString: $0) } ?? "sqlite error \(code)"
            sqlite3_free(errorMessage)
            throw SQLiteDatabaseError.executionFailed(message: message)
        }
    }

    func run(_ sql: String, binds: ((OpaquePointer) throws -> Void)? = nil) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let binds {
            try binds(statement)
        }
        let code = sqlite3_step(statement)
        guard code == SQLITE_DONE || code == SQLITE_ROW else {
            throw SQLiteDatabaseError.stepFailed(message: lastErrorMessage())
        }
    }

    func scalarInt(_ sql: String) throws -> Int {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        guard code == SQLITE_ROW else {
            throw SQLiteDatabaseError.stepFailed(message: lastErrorMessage())
        }
        return Int(sqlite3_column_int64(statement, 0))
    }

    func scalarText(_ sql: String) throws -> String? {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        let code = sqlite3_step(statement)
        if code == SQLITE_DONE {
            return nil
        }
        guard code == SQLITE_ROW else {
            throw SQLiteDatabaseError.stepFailed(message: lastErrorMessage())
        }
        guard let cString = sqlite3_column_text(statement, 0) else {
            return nil
        }
        return String(cString: cString)
    }

    func collect(
        _ sql: String,
        binds: ((OpaquePointer) throws -> Void)? = nil,
        row: (OpaquePointer) throws -> Void
    ) throws {
        let statement = try prepare(sql)
        defer { sqlite3_finalize(statement) }
        if let binds {
            try binds(statement)
        }
        while true {
            let code = sqlite3_step(statement)
            if code == SQLITE_DONE {
                return
            }
            guard code == SQLITE_ROW else {
                throw SQLiteDatabaseError.stepFailed(message: lastErrorMessage())
            }
            try row(statement)
        }
    }

    private func prepare(_ sql: String) throws -> OpaquePointer {
        guard let db else { throw SQLiteDatabaseError.openFailed(code: SQLITE_MISUSE) }
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, sql, -1, &statement, nil)
        guard code == SQLITE_OK, let statement else {
            throw SQLiteDatabaseError.prepareFailed(message: lastErrorMessage())
        }
        return statement
    }

    private func lastErrorMessage() -> String {
        guard let db else { return "no database" }
        return String(cString: sqlite3_errmsg(db))
    }
}

/// Parameter and column helpers for the SQLite C API.
enum SQLiteBinding {
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    static func text(_ statement: OpaquePointer, index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(statement, index, value, -1, transient)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func int(_ statement: OpaquePointer, index: Int32, _ value: Int?) {
        if let value {
            sqlite3_bind_int64(statement, index, Int64(value))
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func double(_ statement: OpaquePointer, index: Int32, _ value: Double?) {
        if let value {
            sqlite3_bind_double(statement, index, value)
        } else {
            sqlite3_bind_null(statement, index)
        }
    }

    static func columnText(_ statement: OpaquePointer, index: Int32) -> String? {
        guard let cString = sqlite3_column_text(statement, index) else { return nil }
        return String(cString: cString)
    }

    static func columnInt(_ statement: OpaquePointer, index: Int32) -> Int {
        Int(sqlite3_column_int64(statement, index))
    }

    static func columnDouble(_ statement: OpaquePointer, index: Int32) -> Double {
        sqlite3_column_double(statement, index)
    }

    static func columnIsNull(_ statement: OpaquePointer, index: Int32) -> Bool {
        sqlite3_column_type(statement, index) == SQLITE_NULL
    }
}
