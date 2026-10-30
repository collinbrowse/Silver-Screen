//
//  WindowTopInsetReaderTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class WindowTopInsetReaderTests: XCTestCase {
    func test_report_deliversAfterTheCurrentPass() async {
        let probe = WindowTopInsetReader.ProbeView()
        var received: [CGFloat] = []
        probe.onChange = { received.append($0) }

        probe.report(top: 59)

        XCTAssertTrue(received.isEmpty)
        await settle(until: { !received.isEmpty })
        XCTAssertEqual(received, [59])
    }

    func test_report_sameInsetTwice_deliversOnce() async {
        let probe = WindowTopInsetReader.ProbeView()
        var received: [CGFloat] = []
        probe.onChange = { received.append($0) }

        probe.report(top: 59)
        probe.report(top: 59)
        probe.report(top: 24)
        await settle(until: { received.count >= 2 })

        XCTAssertEqual(received, [59, 24])
    }

    func test_report_zeroInset_isIgnored() async {
        let probe = WindowTopInsetReader.ProbeView()
        var received: [CGFloat] = []
        probe.onChange = { received.append($0) }

        probe.report(top: 0)
        await settle(until: { false })

        XCTAssertTrue(received.isEmpty)
    }

    private func settle(until done: () -> Bool) async {
        for _ in 0..<50 where !done() {
            await Task.yield()
        }
    }
}
