//
//  FeedbackViewModelTests.swift
//  SilverScreenTests
//

import XCTest
@testable import SilverScreen

@MainActor
final class FeedbackViewModelTests: XCTestCase {
    private var sent: [FeedbackSubmission] = []

    private func makeViewModel(accepts: Bool = true) -> FeedbackViewModel {
        FeedbackViewModel { [unowned self] submission in
            sent.append(submission)
            return accepts
        }
    }

    func test_canSubmit_withBlankMessage_isFalse() {
        let viewModel = makeViewModel()
        viewModel.message = "   \n"

        XCTAssertFalse(viewModel.canSubmit)
    }

    func test_submit_withMessageAndNoEmail_sendsTrimmedMessageAndNilEmail() {
        let viewModel = makeViewModel()
        viewModel.message = "  Love the awards shelves  "
        viewModel.email = "  "

        viewModel.submit()

        XCTAssertEqual(sent, [FeedbackSubmission(message: "Love the awards shelves", email: nil)])
        XCTAssertEqual(viewModel.state, .sent)
    }

    func test_submit_withEmail_sendsTrimmedEmail() {
        let viewModel = makeViewModel()
        viewModel.message = "Add a diary"
        viewModel.email = " me@example.com "

        viewModel.submit()

        XCTAssertEqual(sent.first?.email, "me@example.com")
    }

    func test_emailIsValid_rejectsAddressesWithoutDomainDot() {
        let viewModel = makeViewModel()
        for bad in ["me", "me@", "@example.com", "me@example", "me@.com", "me@example.", "a b@example.com", "a@b@c.com"] {
            viewModel.email = bad
            XCTAssertFalse(viewModel.emailIsValid, bad)
        }
    }

    func test_canSubmit_withInvalidEmail_isFalse() {
        let viewModel = makeViewModel()
        viewModel.message = "Hi"
        viewModel.email = "not-an-email"

        XCTAssertFalse(viewModel.canSubmit)
        viewModel.submit()
        XCTAssertTrue(sent.isEmpty)
    }

    func test_submit_whenSenderUnavailable_setsUnavailable() {
        let viewModel = makeViewModel(accepts: false)
        viewModel.message = "Hi"

        viewModel.submit()

        XCTAssertEqual(viewModel.state, .unavailable)
    }

    func test_submit_afterSent_doesNotSendTwice() {
        let viewModel = makeViewModel()
        viewModel.message = "Hi"

        viewModel.submit()
        viewModel.submit()

        XCTAssertEqual(sent.count, 1)
    }
}
