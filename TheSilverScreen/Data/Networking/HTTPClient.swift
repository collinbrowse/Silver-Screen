//
//  HTTPClient.swift
//  TheSilverScreen
//
//  The only network seam. Repositories talk to this; tests fake it.
//  See .cursor/rules/data-layer.mdc and .cursor/rules/testing.mdc.
//

import Foundation

protocol HTTPClient: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}
