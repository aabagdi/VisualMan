//
//  View+DebouncedSearch.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import SwiftUI

extension View {
  func debouncedSearchable<T>(
    text: Binding<String>,
    results: Binding<[T]?>,
    source: [T],
    keyPaths: @escaping (T) -> [String?]
  ) -> some View {
    self
      .searchable(text: text, placement: .navigationBarDrawer(displayMode: .always))
      .task(id: text.wrappedValue) {
        if text.wrappedValue.isEmpty {
          results.wrappedValue = nil
          return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        results.wrappedValue = source.filtered(by: text.wrappedValue, matching: keyPaths)
      }
  }
}
