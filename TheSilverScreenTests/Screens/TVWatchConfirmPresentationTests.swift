//
//  TVWatchConfirmPresentationTests.swift
//  TheSilverScreenTests
//
//  Documents the SwiftUI alert payload race: isPresented bindings must not clear
//  the confirm payload before the button action captures it.
//

import XCTest
@testable import TheSilverScreen

final class TVWatchConfirmPresentationTests: XCTestCase {
    /// Mimics the broken pattern: dismissing the alert nils the payload that the
    /// confirm button still needs to read.
    func test_clearingPayloadOnDismiss_beforeCapture_dropsConfirmAction() {
        var pending: String? = "markSeason"

        // Alert dismisses (isPresented → false) and clears payload first.
        pending = nil
        let captured = pending

        XCTAssertNil(captured, "Broken dismiss path clears the action before confirm can run")
    }

    /// Correct pattern: capture payload synchronously, then dismiss / clear.
    func test_synchronousCaptureBeforeClear_keepsConfirmAction() {
        var pending: String? = "markSeason"
        var isPresented = true

        let captured = pending
        pending = nil
        isPresented = false

        XCTAssertEqual(captured, "markSeason")
        XCTAssertNil(pending)
        XCTAssertFalse(isPresented)
    }
}
