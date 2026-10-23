//
//  HTTPClient.swift
//  SilverScreen
//
//  The only network seam. Repositories talk to this; tests fake it.
//  See .claude/rules/data-layer.md and .claude/rules/testing.md.
//

import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
