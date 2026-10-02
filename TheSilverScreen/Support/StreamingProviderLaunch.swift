//
//  StreamingProviderLaunch.swift
//  TheSilverScreen
//
//  Opens a streaming provider's iOS app or its App Store listing. Never deep-links to a title.
//

import Foundation
import UIKit

/// TMDB `provider_id` to an on-device app URL scheme and App Store listing.
enum StreamingProviderLaunch {
    struct Destination: Sendable, Equatable {
        let urlScheme: String
        let appStoreURL: URL
    }

    /// URL schemes declared in Info.plist for `canOpenURL` checks.
    static let queriedURLSchemes: [String] = Array(
        Set(destinationsByProviderID.values.map(\.urlScheme))
    ).sorted()

    /// Resolves a tap target for a provider logo. Unknown IDs are not tappable.
    static func destination(for providerID: Int) -> Destination? {
        destinationsByProviderID[providerID]
    }

    /// App URL when the provider app is installed; otherwise the App Store URL.
    static func targetURL(for provider: StreamingProvider, isAppInstalled: (URL) -> Bool) -> URL? {
        guard let destination = destination(for: provider.id),
              let appURL = URL(string: "\(destination.urlScheme)://") else {
            return nil
        }
        return isAppInstalled(appURL) ? appURL : destination.appStoreURL
    }

    @MainActor
    static func targetURL(for provider: StreamingProvider) -> URL? {
        targetURL(for: provider, isAppInstalled: { UIApplication.shared.canOpenURL($0) })
    }

    static func accessibilityLabel(for provider: StreamingProvider, isAppInstalled: (URL) -> Bool) -> String {
        let name = provider.name.isEmpty ? "Streaming app" : provider.name
        guard destination(for: provider.id) != nil else {
            return name
        }
        guard let appURL = destination(for: provider.id).flatMap({ URL(string: "\($0.urlScheme)://") }) else {
            return "Get \(name) on the App Store"
        }
        if isAppInstalled(appURL) {
            return "Open \(name)"
        }
        return "Get \(name) on the App Store"
    }

    /// IDs from TMDB `/watch/providers/movie|tv?watch_region=US` (338 entries). This map covers
    /// first-party services with an iOS app. Amazon Channel, Roku Premium Channel, and cable
    /// network rows are omitted because they do not have their own App Store app.
    private static let destinationsByProviderID: [Int: Destination] = {
        let netflix = Destination(
            urlScheme: "nflx",
            appStoreURL: URL(string: "https://apps.apple.com/app/id363590051")!
        )
        let primeVideo = Destination(
            urlScheme: "aiv",
            appStoreURL: URL(string: "https://apps.apple.com/app/id545519333")!
        )
        let disneyPlus = Destination(
            urlScheme: "disneyplus",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1446075923")!
        )
        let disneyNOW = Destination(
            urlScheme: "disneynow",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1020417862")!
        )
        let hulu = Destination(
            urlScheme: "hulu",
            appStoreURL: URL(string: "https://apps.apple.com/app/id376510438")!
        )
        let max = Destination(
            urlScheme: "max",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1666653815")!
        )
        let paramountPlus = Destination(
            urlScheme: "paramountplus",
            appStoreURL: URL(string: "https://apps.apple.com/app/id530168168")!
        )
        let peacock = Destination(
            urlScheme: "peacock",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1508186374")!
        )
        let appleTV = Destination(
            urlScheme: "videos",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1174078549")!
        )
        let crunchyroll = Destination(
            urlScheme: "crunchyroll",
            appStoreURL: URL(string: "https://apps.apple.com/app/id329913454")!
        )
        let starz = Destination(
            urlScheme: "starz",
            appStoreURL: URL(string: "https://apps.apple.com/app/id550221096")!
        )
        let discoveryPlus = Destination(
            urlScheme: "discoveryplus",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1498327873")!
        )
        let showtime = Destination(
            urlScheme: "sho",
            appStoreURL: URL(string: "https://apps.apple.com/app/id892521564")!
        )
        let pluto = Destination(
            urlScheme: "plutotv",
            appStoreURL: URL(string: "https://apps.apple.com/app/id751712884")!
        )
        let espn = Destination(
            urlScheme: "espn",
            appStoreURL: URL(string: "https://apps.apple.com/app/id317469184")!
        )
        let fubo = Destination(
            urlScheme: "fubotv",
            appStoreURL: URL(string: "https://apps.apple.com/app/id905401434")!
        )
        let youtubeTV = Destination(
            urlScheme: "youtubetv",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1193350206")!
        )
        let youtube = Destination(
            urlScheme: "youtube",
            appStoreURL: URL(string: "https://apps.apple.com/app/id544007664")!
        )
        let amcPlus = Destination(
            urlScheme: "amcplus",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1578728899")!
        )
        let tubi = Destination(
            urlScheme: "tubitv",
            appStoreURL: URL(string: "https://apps.apple.com/app/id886947564")!
        )
        let plex = Destination(
            urlScheme: "plex",
            appStoreURL: URL(string: "https://apps.apple.com/app/id383457673")!
        )
        let mgmPlus = Destination(
            urlScheme: "mgmplus",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1387517160")!
        )
        let mubi = Destination(
            urlScheme: "mubi",
            appStoreURL: URL(string: "https://apps.apple.com/app/id895977599")!
        )
        let shudder = Destination(
            urlScheme: "shudder",
            appStoreURL: URL(string: "https://apps.apple.com/app/id919677087")!
        )
        let acorn = Destination(
            urlScheme: "acorn",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1072008472")!
        )
        let britbox = Destination(
            urlScheme: "britbox",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1422616656")!
        )
        let curiosity = Destination(
            urlScheme: "curiositystream",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1105937304")!
        )
        let criterion = Destination(
            urlScheme: "criterionchannel",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1457718060")!
        )
        let philo = Destination(
            urlScheme: "philo",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1248645354")!
        )
        let sling = Destination(
            urlScheme: "sling",
            appStoreURL: URL(string: "https://apps.apple.com/app/id945075360")!
        )
        let hoichoi = Destination(
            urlScheme: "hoichoi",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1481775110")!
        )
        let viki = Destination(
            urlScheme: "viki",
            appStoreURL: URL(string: "https://apps.apple.com/app/id445553058")!
        )
        let hidive = Destination(
            urlScheme: "hidive",
            appStoreURL: URL(string: "https://apps.apple.com/app/id962376156")!
        )
        let kocowa = Destination(
            urlScheme: "kocowa",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1425703638")!
        )
        let allblk = Destination(
            urlScheme: "allblk",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1140917373")!
        )
        let pureFlix = Destination(
            urlScheme: "pureflix",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1040024556")!
        )
        let hoopla = Destination(
            urlScheme: "hoopla",
            appStoreURL: URL(string: "https://apps.apple.com/app/id580643291")!
        )
        let kanopy = Destination(
            urlScheme: "kanopy",
            appStoreURL: URL(string: "https://apps.apple.com/app/id1205614510")!
        )

        var map: [Int: Destination] = [:]
        func assign(_ destination: Destination, ids: Int...) {
            for id in ids {
                map[id] = destination
            }
        }

        assign(netflix, ids: 8, 273, 175, 1796)
        assign(primeVideo, ids: 9, 119, 613, 2100)
        assign(disneyPlus, ids: 337)
        assign(disneyNOW, ids: 508)
        assign(hulu, ids: 15)
        assign(max, ids: 1899, 384)
        assign(paramountPlus, ids: 531, 2303, 2616)
        assign(peacock, ids: 386, 387)
        assign(appleTV, ids: 350, 2)
        assign(crunchyroll, ids: 283)
        assign(starz, ids: 43)
        assign(discoveryPlus, ids: 520)
        assign(showtime, ids: 37)
        assign(pluto, ids: 300)
        assign(espn, ids: 176, 1718, 1768)
        assign(fubo, ids: 257)
        assign(youtubeTV, ids: 2528)
        assign(youtube, ids: 188, 192, 235)
        assign(amcPlus, ids: 526)
        assign(tubi, ids: 73)
        assign(plex, ids: 538, 2077)
        assign(mgmPlus, ids: 34)
        assign(mubi, ids: 11)
        assign(shudder, ids: 99)
        assign(acorn, ids: 87)
        assign(britbox, ids: 151)
        assign(curiosity, ids: 190)
        assign(criterion, ids: 258)
        assign(philo, ids: 2383)
        assign(sling, ids: 299, 1809)
        assign(hoichoi, ids: 315)
        assign(viki, ids: 344)
        assign(hidive, ids: 430)
        assign(kocowa, ids: 464)
        assign(allblk, ids: 251)
        assign(pureFlix, ids: 278)
        assign(hoopla, ids: 212)
        assign(kanopy, ids: 191)

        return map
    }()
}
