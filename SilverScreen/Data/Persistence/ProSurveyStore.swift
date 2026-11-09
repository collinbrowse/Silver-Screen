//
//  ProSurveyStore.swift
//  SilverScreen
//
//  What the survey remembers on the device, in UserDefaults: the random response
//  ID, the last answers sent, whether the Library card was dismissed or shown,
//  and which days the app was opened (for when the card appears). Keys carry the
//  survey id, so a new survey starts fresh.
//

import Foundation

/// UserDefaults-backed survey state. Holds a suite name rather than the instance,
/// because `UserDefaults` is not `Sendable`.
struct ProSurveyStore: Sendable {
    /// Days kept for the open-day count; the card only needs a few.
    static let maxDaysKept = 30

    let suiteName: String?
    let surveyID: String

    init(suiteName: String? = nil, surveyID: String = ProSurvey.id) {
        self.suiteName = suiteName
        self.surveyID = surveyID
    }

    private var defaults: UserDefaults {
        suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
    }

    private func key(_ name: String) -> String {
        "proSurvey.\(surveyID).\(name)"
    }

    /// A random UUID made on first use. Not the analytics install ID, and not derived
    /// from the device or anything the person typed.
    func responseID() -> String {
        if let existing = defaults.string(forKey: key("responseID")), UUID(uuidString: existing) != nil {
            return existing
        }
        let fresh = UUID().uuidString
        defaults.set(fresh, forKey: key("responseID"))
        return fresh
    }

    /// The answers last accepted by the Worker, or nil before the first send.
    func savedAnswers() -> ProSurveyAnswers? {
        guard let raw = defaults.stringArray(forKey: key("features")) else { return nil }
        let features = Set(raw.compactMap(ProFeature.init(rawValue:)))
        return ProSurveyAnswers(features: features, other: defaults.string(forKey: key("other")))
    }

    func saveAnswers(_ answers: ProSurveyAnswers) {
        defaults.set(answers.features.map(\.rawValue).sorted(), forKey: key("features"))
        if let other = answers.other {
            defaults.set(other, forKey: key("other"))
        } else {
            defaults.removeObject(forKey: key("other"))
        }
    }

    var isCardDismissed: Bool {
        defaults.bool(forKey: key("cardDismissed"))
    }

    func dismissCard() {
        defaults.set(true, forKey: key("cardDismissed"))
    }

    /// True once the card has been counted as shown, so `ProSurvey.cardShown` goes out once.
    var wasCardShown: Bool {
        defaults.bool(forKey: key("cardShown"))
    }

    func markCardShown() {
        defaults.set(true, forKey: key("cardShown"))
    }

    /// Records that the app was opened on `day` (`yyyy-MM-dd`) and returns how many
    /// distinct days it has been opened since the survey shipped.
    @discardableResult
    func recordOpen(day: String) -> Int {
        var days = defaults.stringArray(forKey: key("daysOpened")) ?? []
        if !days.contains(day) {
            days.append(day)
            days = Array(days.suffix(Self.maxDaysKept))
            defaults.set(days, forKey: key("daysOpened"))
        }
        return days.count
    }

    var daysOpened: Int {
        defaults.stringArray(forKey: key("daysOpened"))?.count ?? 0
    }
}
