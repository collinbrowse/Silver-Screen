//
//  TMDBWatchProvidersDecoding.swift
//  TheSilverScreen
//
//  Reads TMDB watch-provider payloads. A bad block does not fail the detail screen.
//

import Foundation

/// One row from TMDB's flatrate, rent, or buy lists.
struct TMDBWatchProviderDTO: Decodable, Sendable, Equatable {
    let providerID: Int
    let providerName: String
    let logoPath: String?
    let displayPriority: Int?

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case logoPath = "logo_path"
        case displayPriority = "display_priority"
    }
}

/// Picks flatrate providers for the device region from a TMDB watch-providers block.
enum TMDBWatchProviders {
    static func make(from results: [String: RegionProviders], locale: Locale) -> [StreamingProvider] {
        let region = TMDBLocale.regionCode(for: locale) ?? "US"
        let regionKey = results.keys.first { $0.caseInsensitiveCompare(region) == .orderedSame }
        let fallbackKey = regionKey ?? results.keys.first { $0.caseInsensitiveCompare("US") == .orderedSame }
        guard let key = fallbackKey ?? results.keys.sorted().first,
              let flatrate = results[key]?.flatrate else {
            return []
        }
        struct Candidate {
            let dto: TMDBWatchProviderDTO
            let primaryID: Int
            let priority: Int
        }

        var bestByPrimary: [Int: Candidate] = [:]

        for provider in flatrate {
            let path = provider.logoPath?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !path.isEmpty else { continue }
            let name = provider.providerName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty,
                  StreamingProviderCore.shouldInclude(providerID: provider.providerID, name: name) else {
                continue
            }

            let priority = provider.displayPriority ?? Int.max
            for primaryID in StreamingProviderCore.primaryIDs(for: provider.providerID, name: name) {
                if let existing = bestByPrimary[primaryID], existing.priority <= priority {
                    continue
                }
                bestByPrimary[primaryID] = Candidate(dto: provider, primaryID: primaryID, priority: priority)
            }
        }

        return bestByPrimary.values
            .sorted { lhs, rhs in
                if lhs.priority != rhs.priority { return lhs.priority < rhs.priority }
                let leftName = StreamingProviderCore.displayName(primaryID: lhs.primaryID, tmdbName: lhs.dto.providerName)
                let rightName = StreamingProviderCore.displayName(primaryID: rhs.primaryID, tmdbName: rhs.dto.providerName)
                return leftName.localizedCaseInsensitiveCompare(rightName) == .orderedAscending
            }
            .map { candidate in
                StreamingProvider(
                    id: candidate.primaryID,
                    name: StreamingProviderCore.displayName(
                        primaryID: candidate.primaryID,
                        tmdbName: candidate.dto.providerName
                    ),
                    logoPath: candidate.dto.logoPath
                )
            }
            .filter { !$0.name.isEmpty }
    }

    struct RegionProviders: Decodable, Sendable, Equatable {
        let flatrate: [TMDBWatchProviderDTO]?
    }
}

/// Reads watch providers from a detail append block or a watch/providers endpoint.
enum TMDBWatchProvidersDecoding {
    static func providers(
        from data: Data,
        locale: Locale,
        logger: any AppLogging,
        context: String
    ) -> [StreamingProvider] {
        do {
            let results = try decodeResults(from: data)
            return TMDBWatchProviders.make(from: results, locale: locale)
        } catch {
            logger.error("\(context) skipped malformed watch providers", category: .networking)
            return []
        }
    }

    private static func decodeResults(from data: Data) throws -> [String: TMDBWatchProviders.RegionProviders] {
        if let appended = try? JSONDecoder().decode(AppendedEnvelope.self, from: data),
           let results = appended.watchProviders?.results {
            return results
        }
        let standalone = try JSONDecoder().decode(StandaloneEnvelope.self, from: data)
        return standalone.results ?? [:]
    }

    private struct AppendedEnvelope: Decodable {
        let watchProviders: WatchProvidersBlock?

        enum CodingKeys: String, CodingKey {
            case watchProviders = "watch/providers"
        }
    }

    private struct StandaloneEnvelope: Decodable {
        let results: [String: TMDBWatchProviders.RegionProviders]?
    }

    private struct WatchProvidersBlock: Decodable {
        let results: [String: TMDBWatchProviders.RegionProviders]?
    }
}
