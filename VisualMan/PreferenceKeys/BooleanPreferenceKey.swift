//
//  BooleanPreferenceKey.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/30/25.
//

import Foundation
import SwiftUI

struct BooleanPreferenceKey: PreferenceKey {
  static var defaultValue: Bool = true
  
  static func reduce(value: inout Bool, nextValue: () -> Bool) {
    value = value && nextValue()
  }
}
