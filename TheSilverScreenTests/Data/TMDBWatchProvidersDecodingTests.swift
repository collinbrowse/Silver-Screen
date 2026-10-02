//
//  TMDBWatchProvidersDecodingTests.swift
//  TheSilverScreenTests
//

import XCTest
@testable import TheSilverScreen

final class TMDBWatchProvidersDecodingTests: XCTestCase {
    func test_make_usesDeviceRegionAndSortsByDisplayPriority() {
        let results: [String: TMDBWatchProviders.RegionProviders] = [
            "US": TMDBWatchProviders.RegionProviders(flatrate: [
                TMDBWatchProviderDTO(
                    providerID: 2,
                    providerName: "Apple TV",
                    logoPath: "/apple.jpg",
                    displayPriority: 5
                ),
                TMDBWatchProviderDTO(
                    providerID: 8,
                    providerName: "Netflix",
                    logoPath: "/netflix.jpg",
                    displayPriority: 1
                ),
            ]),
        ]
        let locale = Locale(identifier: "en_US")
        let providers = TMDBWatchProviders.make(from: results, locale: locale)
        XCTAssertEqual(providers.map(\.name), ["Netflix", "Apple TV"])
        XCTAssertEqual(providers.map(\.id), [8, 350])
    }

    func test_make_dropsRentAndBuyAndBlankLogos() {
        let json = Data("""
            {
              "results": {
                "US": {
                  "flatrate": [
                    {"provider_id": 1, "provider_name": "Good", "logo_path": "/good.jpg", "display_priority": 0},
                    {"provider_id": 2, "provider_name": "Blank", "logo_path": "  ", "display_priority": 0}
                  ],
                  "rent": [
                    {"provider_id": 3, "provider_name": "Rent", "logo_path": "/rent.jpg", "display_priority": 0}
                  ]
                }
              }
            }
            """.utf8)
        let providers = TMDBWatchProvidersDecoding.providers(
            from: json,
            locale: Locale(identifier: "en_US"),
            logger: SilentLogger(),
            context: "test"
        )
        XCTAssertEqual(providers.map(\.name), ["Good"])
    }

    func test_providers_readsAppendedWatchProvidersBlock() {
        let json = Data("""
            {
              "id": 1,
              "title": "Dune",
              "watch/providers": {
                "results": {
                  "US": {
                    "flatrate": [
                      {"provider_id": 9, "provider_name": "Prime", "logo_path": "/prime.jpg", "display_priority": 2}
                    ]
                  }
                }
              }
            }
            """.utf8)
        let providers = TMDBWatchProvidersDecoding.providers(
            from: json,
            locale: Locale(identifier: "en_US"),
            logger: SilentLogger(),
            context: "test"
        )
        XCTAssertEqual(providers.map(\.name), ["Prime Video"])
        XCTAssertEqual(providers.map(\.id), [9])
    }

    func test_providers_malformedPayloadReturnsEmpty() {
        let providers = TMDBWatchProvidersDecoding.providers(
            from: Data("{}".utf8),
            locale: Locale(identifier: "en_US"),
            logger: SilentLogger(),
            context: "test"
        )
        XCTAssertTrue(providers.isEmpty)
    }

    func test_make_collapsesAdTierVariantsToCoreProvider() {
        let results: [String: TMDBWatchProviders.RegionProviders] = [
            "US": TMDBWatchProviders.RegionProviders(flatrate: [
                TMDBWatchProviderDTO(
                    providerID: 1796,
                    providerName: "Netflix Standard with Ads",
                    logoPath: "/netflix-ads.jpg",
                    displayPriority: 1
                ),
                TMDBWatchProviderDTO(
                    providerID: 8,
                    providerName: "Netflix",
                    logoPath: "/netflix.jpg",
                    displayPriority: 2
                ),
                TMDBWatchProviderDTO(
                    providerID: 613,
                    providerName: "Amazon Prime Video Free with Ads",
                    logoPath: "/prime.jpg",
                    displayPriority: 3
                ),
            ]),
        ]
        let providers = TMDBWatchProviders.make(from: results, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(providers.map(\.name), ["Netflix", "Prime Video"])
        XCTAssertEqual(providers.map(\.id), [8, 9])
    }

    func test_make_excludesAmazonChannelBundles() {
        let results: [String: TMDBWatchProviders.RegionProviders] = [
            "US": TMDBWatchProviders.RegionProviders(flatrate: [
                TMDBWatchProviderDTO(
                    providerID: 582,
                    providerName: "Paramount+ Amazon Channel",
                    logoPath: "/paramount-channel.jpg",
                    displayPriority: 0
                ),
                TMDBWatchProviderDTO(
                    providerID: 531,
                    providerName: "Paramount Plus",
                    logoPath: "/paramount.jpg",
                    displayPriority: 1
                ),
            ]),
        ]
        let providers = TMDBWatchProviders.make(from: results, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(providers.map(\.name), ["Paramount+"])
        XCTAssertEqual(providers.map(\.id), [531])
    }

    func test_make_splitsRecognizedComboNamesIntoCoreProviders() {
        let results: [String: TMDBWatchProviders.RegionProviders] = [
            "US": TMDBWatchProviders.RegionProviders(flatrate: [
                TMDBWatchProviderDTO(
                    providerID: 9999,
                    providerName: "Prime Video + Paramount+",
                    logoPath: "/combo.jpg",
                    displayPriority: 0
                ),
            ]),
        ]
        let providers = TMDBWatchProviders.make(from: results, locale: Locale(identifier: "en_US"))
        XCTAssertEqual(providers.map(\.name), ["Paramount+", "Prime Video"])
        XCTAssertEqual(providers.map(\.id), [531, 9])
    }
}
