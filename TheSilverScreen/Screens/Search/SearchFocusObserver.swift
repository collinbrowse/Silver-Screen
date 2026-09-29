//
//  SearchFocusObserver.swift
//  TheSilverScreen
//
//  Reads whether the system search field is focused. Lives under `.searchable`
//  so it can see `isSearching`, which the search screen itself cannot.
//

import SwiftUI

struct SearchFocusObserver: View {
    var onChange: (Bool) -> Void
    @Environment(\.isSearching) private var isSearching

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .onAppear { onChange(isSearching) }
            .onChange(of: isSearching) { _, focused in
                onChange(focused)
            }
    }
}
