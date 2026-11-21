//
//  Array+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

import Foundation

extension Array {
  func filtered(by searchText: String,
                matching keyPaths: (Element) -> [String?]) -> [Element] {
    guard !searchText.isEmpty else { return self }
    return filter { element in
      keyPaths(element).contains { field in
        field?.localizedStandardContains(searchText) ?? false
      }
    }
  }
}
