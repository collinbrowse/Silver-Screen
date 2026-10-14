//
//  MarketingCaptureTests.swift
//  SilverScreenUITests
//
//  Plays the website tour from marketing/titles.json while scripts/marketing.py
//  records the screen. App Store screenshots need no taps, so the script takes
//  those itself. The script passes the titles file and an output folder through
//  TEST_RUNNER_ environment variables; without them the test skips, so a plain UI
//  test run never records anything.
//

import XCTest

final class MarketingCaptureTests: XCTestCase {
    /// One clip to record, as written in titles.json.
    private struct Step: Decodable {
        let id: String
        /// A `RouterSnapshot` the app opens on. Passed through as JSON.
        let route: JSONValue?
        let actions: [Action]?
        /// A seeded list to open on Library, by name.
        let openList: String?
        /// Limit to `iphone` or `ipad`. Missing means both.
        let devices: [String]?
        /// Seconds to hold the final frame of a tour clip.
        let hold: Double?
    }

    /// A tiny script language so a shot can change without touching Swift.
    private struct Action: Decodable {
        var tap: String?
        var tapContaining: String?
        var tapCell: Int?
        var search: String?
        /// Drags the first slider to this position (0...1), like a finger would.
        var slide: Double?
        /// Types into the field whose label contains `into`.
        var type: String?
        var into: String?
        var swipeUp: Int?
        var swipeDown: Int?
        var swipeLeft: Int?
        var scrollTo: String?
        var waitFor: String?
        var wait: Double?
        /// Swipe more slowly for a tour clip.
        var slow: Bool?
    }

    private struct Config: Decodable {
        let tour: [Step]
    }

    private var config: Config!
    private var titlesPath = ""
    private var outputURL: URL!
    private var device = "iphone"

    override func setUpWithError() throws {
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        guard
            let titles = environment["SS_MARKETING_TITLES"],
            let output = environment["SS_MARKETING_OUT"]
        else {
            throw XCTSkip("Run through scripts/marketing.py to capture marketing assets.")
        }
        titlesPath = titles
        outputURL = URL(fileURLWithPath: output, isDirectory: true)
        device = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
        try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)
        config = try JSONDecoder().decode(Config.self, from: Data(contentsOf: URL(fileURLWithPath: titles)))
        XCUIDevice.shared.orientation = .portrait
        Quiescence.disable()
    }

    /// Plays each tour clip at a human pace and writes when it started and ended,
    /// so the script can cut the screen recording into one file per clip.
    func test_playTour() throws {
        var markers: [[String: Any]] = []
        for clip in config.tour where clip.devices?.contains(device) ?? true {
            let app = launch(clip)
            settle()
            let start = Date().timeIntervalSince1970
            try run(clip.actions ?? [], in: app, slow: true)
            Thread.sleep(forTimeInterval: clip.hold ?? 1.5)
            markers.append(["id": clip.id, "start": start, "end": Date().timeIntervalSince1970])
            app.terminate()
        }
        let data = try JSONSerialization.data(withJSONObject: markers, options: [.prettyPrinted])
        try data.write(to: outputURL.appendingPathComponent("tour-markers.json"))
    }

    // MARK: - Launch and actions

    private func launch(_ step: Step) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["SS_DEMO_MODE"] = "1"
        app.launchEnvironment["SS_DEMO_SEED"] = titlesPath
        if let route = step.route, let data = try? JSONEncoder().encode(route) {
            app.launchEnvironment["SS_DEMO_ROUTE"] = String(decoding: data, as: UTF8.self)
        }
        if let list = step.openList {
            app.launchEnvironment["SS_DEMO_OPEN_LIST"] = list
        }
        app.launch()
        _ = app.tabBars.firstMatch.waitForExistence(timeout: 20)
        return app
    }

    private func run(_ actions: [Action], in app: XCUIApplication, slow: Bool) throws {
        for action in actions {
            let pace = slow || action.slow == true
            if let label = action.tap {
                try element(app, label: label, containing: false).tap()
            }
            if let label = action.tapContaining {
                try element(app, label: label, containing: true).tap()
            }
            if let index = action.tapCell {
                let cell = app.cells.element(boundBy: index)
                XCTAssertTrue(cell.waitForExistence(timeout: 15), "No cell \(index)")
                cell.tap()
            }
            if let query = action.search {
                let field = app.searchFields.firstMatch
                XCTAssertTrue(field.waitForExistence(timeout: 15), "No search field")
                field.tap()
                if pace {
                    for character in query {
                        field.typeText(String(character))
                        Thread.sleep(forTimeInterval: 0.09)
                    }
                } else {
                    field.typeText(query)
                }
            }
            if let position = action.slide {
                let slider = app.sliders.firstMatch
                XCTAssertTrue(slider.waitForExistence(timeout: 15), "No slider")
                let start = slider.coordinate(withNormalizedOffset: CGVector(dx: 0.03, dy: 0.5))
                let end = slider.coordinate(withNormalizedOffset: CGVector(dx: position, dy: 0.5))
                start.press(forDuration: 0.15, thenDragTo: end, withVelocity: pace ? 250 : .fast, thenHoldForDuration: 0.2)
            }
            if let text = action.type {
                let field = try element(app, label: action.into ?? "", containing: true)
                field.tap()
                if pace {
                    for character in text {
                        field.typeText(String(character))
                        Thread.sleep(forTimeInterval: 0.06)
                    }
                } else {
                    field.typeText(text)
                }
            }
            for _ in 0..<(action.swipeUp ?? 0) {
                swipe(app, from: CGVector(dx: 0.5, dy: 0.75), to: CGVector(dx: 0.5, dy: 0.3), slow: pace)
            }
            for _ in 0..<(action.swipeDown ?? 0) {
                swipe(app, from: CGVector(dx: 0.5, dy: 0.3), to: CGVector(dx: 0.5, dy: 0.75), slow: pace)
            }
            for _ in 0..<(action.swipeLeft ?? 0) {
                swipe(app, from: CGVector(dx: 0.85, dy: 0.5), to: CGVector(dx: 0.15, dy: 0.5), slow: pace)
            }
            if let label = action.scrollTo {
                var attempts = 0
                while !anyElement(app, label: label, containing: true).isHittable, attempts < 8 {
                    swipe(app, from: CGVector(dx: 0.5, dy: 0.7), to: CGVector(dx: 0.5, dy: 0.4), slow: pace)
                    attempts += 1
                }
            }
            if let label = action.waitFor {
                XCTAssertTrue(anyElement(app, label: label, containing: true).waitForExistence(timeout: 20), "Never saw \(label)")
            }
            if let seconds = action.wait {
                Thread.sleep(forTimeInterval: seconds)
            } else if pace {
                Thread.sleep(forTimeInterval: 0.9)
            }
        }
    }

    private func element(_ app: XCUIApplication, label: String, containing: Bool) throws -> XCUIElement {
        let match = anyElement(app, label: label, containing: containing)
        XCTAssertTrue(match.waitForExistence(timeout: 15), "No element labeled \(label)")
        return match
    }

    /// Buttons first so a tab or control wins over static text with the same words.
    private func anyElement(_ app: XCUIApplication, label: String, containing: Bool) -> XCUIElement {
        func predicate() -> NSPredicate {
            containing
                ? NSPredicate(format: "label CONTAINS[c] %@", label)
                : NSPredicate(format: "label == %@", label)
        }
        let button = app.buttons.matching(predicate()).firstMatch
        if button.exists { return button }
        return app.descendants(matching: .any).matching(predicate()).firstMatch
    }

    private func swipe(_ app: XCUIApplication, from start: CGVector, to end: CGVector, slow: Bool) {
        let window = app.windows.firstMatch
        let from = window.coordinate(withNormalizedOffset: start)
        let to = window.coordinate(withNormalizedOffset: end)
        from.press(
            forDuration: 0.05,
            thenDragTo: to,
            withVelocity: slow ? 900 : XCUIGestureVelocity.fast,
            thenHoldForDuration: 0.1
        )
    }

    /// Gives posters and backdrops time to load before a capture.
    private func settle() {
        Thread.sleep(forTimeInterval: 3)
    }
}

/// XCUITest waits for the app to go idle before every step. On a busy simulator that
/// wait can run for minutes and leaves dead air in the recording. The tour sets its own
/// pace with explicit waits, so the idle wait is replaced with a no-op.
private enum Quiescence {
    static func disable() {
        guard let process = NSClassFromString("XCUIApplicationProcess") else { return }
        for name in ["waitForQuiescenceIncludingAnimationsIdle:isPreEvent:", "waitForQuiescenceIncludingAnimationsIdle:"] {
            guard let method = class_getInstanceMethod(process, NSSelectorFromString(name)) else { continue }
            let noWait: @convention(block) (AnyObject, Bool, Bool) -> Void = { _, _, _ in }
            method_setImplementation(method, imp_implementationWithBlock(noWait))
        }
    }
}

/// Any JSON value, so a route passes from titles.json to the app untouched.
private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([JSONValue])
    case object([String: JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
            case .string(let value): try container.encode(value)
            case .number(let value):
                if value.rounded() == value, abs(value) < 1e15 {
                    try container.encode(Int(value))
                } else {
                    try container.encode(value)
                }
            case .bool(let value): try container.encode(value)
            case .array(let value): try container.encode(value)
            case .object(let value): try container.encode(value)
            case .null: try container.encodeNil()
        }
    }
}
