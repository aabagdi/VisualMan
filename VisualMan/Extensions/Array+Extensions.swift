//
//  Array+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import Foundation

extension Array {
  subscript(safe index: Int) -> Element? {
    return indices.contains(index) ? self[index] : nil
  }
}
