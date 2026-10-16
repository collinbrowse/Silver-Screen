//
//  SettingsView.swift
//  SilverScreen
//
//  Feedback, support and privacy links, data credits with TMDB's logo, and the app version.
//  Opens as a sheet from Library.
//

import SwiftUI

/// What Settings needs from the composition root.
struct SettingsContext {
    let appInfo: AppInfo
    let sendFeedback: @MainActor (FeedbackSubmission) -> Bool
}

/// Pages inside the Settings sheet. Kept off `Route` so Settings never lands in tab restoration.
enum SettingsDestination: Hashable {
    case feedback
    case acknowledgements
}

struct SettingsView: View {
    let context: SettingsContext
    @Environment(\.dismiss) private var dismiss
    /// TMDB's attribution asks for its logo near the API notice, less prominent than our own branding.
    @ScaledMetric(relativeTo: .footnote) private var tmdbLogoHeight: CGFloat = 12

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink(value: SettingsDestination.feedback) {
                        Label("Send Feedback", systemImage: "bubble.left.and.text.bubble.right")
                    }
                    Link(destination: AppLinks.support) {
                        Label("Help & Support", systemImage: "questionmark.circle")
                    }
                }

                Section {
                    Link(destination: AppLinks.privacyPolicy) {
                        Label("Privacy Policy", systemImage: "hand.raised")
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("Your lists, ratings, and notes stay on this device. Crash reports and feedback you send go to the developer without your name.")
                }

                Section {
                    creditLink("Movies and TV", source: "TMDB", url: AppLinks.tmdb)
                    creditLink("Streaming availability", source: "JustWatch", url: AppLinks.justWatch)
                    creditLink("Awards", source: "Wikidata", url: AppLinks.wikidata)
                    creditLink("Person pages", source: "IMDb", url: AppLinks.imdb)
                } header: {
                    Text("Data Sources")
                } footer: {
                    VStack(alignment: .leading, spacing: DesignSpacing.sm) {
                        Image("TMDBLogo")
                            .resizable()
                            .scaledToFit()
                            .frame(height: tmdbLogoHeight)
                            .accessibilityLabel("The Movie Database (TMDB) logo")
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                    }
                }

                Section {
                    NavigationLink("Acknowledgements", value: SettingsDestination.acknowledgements)
                } footer: {
                    Text("Silver Screen \(context.appInfo.versionLabel)")
                        .frame(maxWidth: .infinity)
                        .padding(.top, DesignSpacing.lg)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .navigationDestination(for: SettingsDestination.self) { destination in
                switch destination {
                    case .feedback:
                        FeedbackView(viewModel: FeedbackViewModel(send: context.sendFeedback))
                    case .acknowledgements:
                        AcknowledgementsView()
                }
            }
        }
    }

    private func creditLink(_ title: String, source: String, url: URL) -> some View {
        Link(destination: url) {
            LabeledContent(title, value: source)
                .foregroundStyle(DesignTheme.textPrimary)
        }
        .accessibilityLabel("\(title) from \(source)")
        .accessibilityHint("Opens \(source) in your browser")
    }
}
