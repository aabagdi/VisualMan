//
//  TimeInterval+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import Foundation

extension TimeInterval {
  func formattedDuration() -> String? {
    guard self > 0 else { return nil }
    let minutes = Int(self) / 60
    let seconds = Int(self) % 60
    return String(format: "%d:%02d", minutes, seconds)
  }
}
