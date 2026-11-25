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
    return Duration.seconds(Int(self)).formatted(.time(pattern: .minuteSecond))
  }
}
