//
//  StreamingProviderCore.swift
//  TheSilverScreen
//
//  Collapses TMDB flatrate rows (ad tiers, bundles) to one logo per core service.
//

import Foundation

/// Maps TMDB watch-provider rows to a single core brand for display and deep links.
enum StreamingProviderCore {
    /// Whether this flatrate row should appear in the hero (channel add-ons are omitted).
    static func shouldInclude(providerID: Int, name: String) -> Bool {
        let lowered = name.lowercased()
        if lowered.contains("amazon channel") { return false }
        if lowered.contains("roku premium channel") { return false }
        if lowered.contains("apple tv channel") { return false }
        return true
    }

    /// Primary TMDB id for a variant row (e.g. Netflix Standard with Ads → Netflix).
    static func primaryID(for providerID: Int) -> Int {
        variantToPrimary[providerID] ?? providerID
    }

    /// User-facing label for a core service.
    static func displayName(primaryID: Int, tmdbName: String) -> String {
        if let fixed = primaryDisplayNames[primaryID] {
            return fixed
        }
        return normalizeTierSuffix(tmdbName)
    }

    /// Expands a TMDB row into one or more primary ids (combo names become multiple cores).
    static func primaryIDs(for providerID: Int, name: String) -> [Int] {
        if let combo = primaryIDsFromComboName(name) {
            return combo
        }
        if name.contains(" + ") {
            let first = normalizeTierSuffix(
                name.components(separatedBy: " + ").first?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? name
            )
            if let id = primaryID(matchingNormalizedName: first) {
                return [id]
            }
        }
        return [primaryID(for: providerID)]
    }

    /// Strips ad/tier suffixes TMDB appends to core service names.
    static func normalizeTierSuffix(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let suffixes = [
            " Standard with Ads",
            " Basic with Ads",
            " Free with Ads",
            " with Ads",
            " Standard",
            " Basic",
            " Premium Plus",
        ]
        var changed = true
        while changed {
            changed = false
            for suffix in suffixes {
                if let range = result.range(of: suffix, options: [.caseInsensitive, .backwards]) {
                    result.removeSubrange(range)
                    changed = true
                }
            }
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func primaryIDsFromComboName(_ name: String) -> [Int]? {
        guard name.contains(" + ") else { return nil }
        let parts = name.components(separatedBy: " + ")
            .map { normalizeTierSuffix($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.isEmpty }
        guard parts.count >= 2 else { return nil }
        let ids = parts.compactMap { primaryID(matchingNormalizedName: $0) }
        guard ids.count == parts.count else { return nil }
        return ids
    }

    private static func primaryID(matchingNormalizedName name: String) -> Int? {
        let key = name.lowercased()
        return nameToPrimaryID[key]
    }

    private static let primaryDisplayNames: [Int: String] = [
        8: "Netflix",
        9: "Prime Video",
        337: "Disney+",
        508: "DisneyNOW",
        15: "Hulu",
        1899: "Max",
        531: "Paramount+",
        386: "Peacock",
        350: "Apple TV",
        283: "Crunchyroll",
        43: "Starz",
        520: "Discovery+",
        37: "Showtime",
        300: "Pluto TV",
        176: "ESPN",
        257: "fuboTV",
        2528: "YouTube TV",
        188: "YouTube",
        526: "AMC+",
        73: "Tubi",
        538: "Plex",
        34: "MGM+",
        11: "MUBI",
        99: "Shudder",
        87: "Acorn TV",
        151: "BritBox",
        190: "Curiosity Stream",
        258: "Criterion Channel",
        2383: "Philo",
        299: "Sling TV",
    ]

    private static let variantToPrimary: [Int: Int] = [
        273: 8, 175: 8, 1796: 8,
        119: 9, 613: 9, 2100: 9,
        384: 1899,
        2303: 531, 2616: 531,
        387: 386,
        2: 350,
        1718: 176, 1768: 176,
        192: 188, 235: 188,
        2077: 538,
        1809: 299,
    ]

    private static let nameToPrimaryID: [String: Int] = {
        var map: [String: Int] = [:]
        func alias(_ names: String..., primary: Int) {
            for name in names {
                map[name.lowercased()] = primary
            }
        }
        alias("netflix", primary: 8)
        alias("amazon prime video", "prime video", primary: 9)
        alias("disney+", "disney plus", primary: 337)
        alias("disneynow", "disney now", primary: 508)
        alias("hulu", primary: 15)
        alias("max", "hbo max", primary: 1899)
        alias("paramount+", "paramount plus", primary: 531)
        alias("peacock", "peacock premium", "peacock premium plus", primary: 386)
        alias("apple tv", primary: 350)
        alias("crunchyroll", primary: 283)
        alias("starz", primary: 43)
        alias("discovery+", "discovery +", "discovery plus", primary: 520)
        alias("showtime", primary: 37)
        alias("pluto tv", primary: 300)
        alias("espn", "espn+", primary: 176)
        alias("fubotv", "fubo tv", primary: 257)
        alias("youtube tv", primary: 2528)
        alias("youtube", "youtube premium", primary: 188)
        alias("amc+", "amc plus", primary: 526)
        alias("tubi", "tubi tv", primary: 73)
        alias("plex", primary: 538)
        alias("mgm+", "mgm plus", primary: 34)
        alias("mubi", primary: 11)
        alias("shudder", primary: 99)
        alias("acorn tv", primary: 87)
        alias("britbox", primary: 151)
        alias("curiosity stream", primary: 190)
        alias("criterion channel", primary: 258)
        alias("philo", primary: 2383)
        alias("sling tv", "sling", primary: 299)
        return map
    }()
}
