//
//  FuzzyTextMatch.swift
//  TheSilverScreen
//
//  Near-miss matching for type-ahead. A typed name can drop or add a couple
//  of letters and still count as the same title or person.
//

import Foundation

/// Compares a typed query with a title or person name. No network.
enum FuzzyTextMatch {
    /// True when every query word lines up, in order, with a word in `candidate`.
    /// A word may be a prefix or a few edits off. Extra candidate words, such as a leading "The", are skipped.
    static func matches(query: String, candidate: String) -> Bool {
        let queryTokens = tokens(in: query)
        guard !queryTokens.isEmpty else { return false }
        let candidateTokens = tokens(in: candidate)
        var candidateIndex = 0
        for queryToken in queryTokens {
            var found = false
            while candidateIndex < candidateTokens.count {
                let candidateToken = candidateTokens[candidateIndex]
                candidateIndex += 1
                if tokenMatches(queryToken, candidateToken) {
                    found = true
                    break
                }
            }
            if !found { return false }
        }
        return true
    }

    /// Words long enough to search on their own when the full query has no close hit.
    /// At most two, in the order they were typed. A word that is the whole query is left out — that search already ran.
    static func fallbackTokens(in query: String) -> [String] {
        let words = tokens(in: query)
        let foldedQuery = words.joined(separator: " ")
        return Array(words.filter { $0.count >= 4 && $0 != foldedQuery }.prefix(2))
    }

    /// Case and diacritics folded, split on anything that is not a letter or digit.
    private static func tokens(in text: String) -> [String] {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var tokens: [String] = []
        var current = ""
        for character in folded {
            if character.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
                current.append(character)
            } else if !current.isEmpty {
                tokens.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }

    private static func tokenMatches(_ queryToken: String, _ candidateToken: String) -> Bool {
        if candidateToken.hasPrefix(queryToken) { return true }
        let budget = editBudget(for: max(queryToken.count, candidateToken.count))
        return editDistance(queryToken, candidateToken, limit: budget) <= budget
    }

    /// 0 edits under 3 characters, 1 edit for 3–5, 2 edits after that.
    private static func editBudget(for length: Int) -> Int {
        switch length {
        case ..<3: 0
        case 3...5: 1
        default: 2
        }
    }

    /// Levenshtein distance, or `limit + 1` once the distance is known to exceed `limit`.
    private static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        if lhs == rhs { return 0 }
        let a = Array(lhs)
        let b = Array(rhs)
        if abs(a.count - b.count) > limit { return limit + 1 }
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }

        var previous = Array(0...b.count)
        var current = Array(repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            var rowMin = current[0]
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(
                    previous[j] + 1,
                    current[j - 1] + 1,
                    previous[j - 1] + cost
                )
                rowMin = min(rowMin, current[j])
            }
            if rowMin > limit { return limit + 1 }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
