//
//  SizePreferenceKey.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/30/25.
//

import Foundation
import SwiftUI

struct SizePreferenceKey: PreferenceKey {
  static var defaultValue: CGSize = .zero
  static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
    value = nextValue()
  }
}
