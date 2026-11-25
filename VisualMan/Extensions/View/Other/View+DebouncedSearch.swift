//
//  View+DebouncedSearch.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import SwiftUI
import Dependencies

extension View {
  func debouncedSearchable<T: Equatable>(
    text: Binding<String>,
    results: Binding<[T]?>,
    source: [T],
    keyPaths: @escaping (T) -> [String?]
  ) -> some View {
    self
      .searchable(text: text, placement: .navigationBarDrawer(displayMode: .always))
      .task(id: DebouncedSearchKey(text: text.wrappedValue, source: source)) {
        @Dependency(\.continuousClock) var clock
        if text.wrappedValue.isEmpty {
          results.wrappedValue = nil
          return
        }
        try? await clock.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        results.wrappedValue = source.filtered(by: text.wrappedValue, matching: keyPaths)
      }
  }
}

private struct DebouncedSearchKey<Element: Equatable>: Equatable {
  let text: String
  let source: [Element]
}
