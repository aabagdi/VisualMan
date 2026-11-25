//
//  BinaryFloatingPoint+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/20/25.
//

import Foundation

extension BinaryFloatingPoint {
  func asTimeString() -> String {
    guard isFinite else { return "" }
    let seconds = Int(self)
    let pattern: Duration.TimeFormatStyle.Pattern = seconds >= 3600
      ? .hourMinuteSecond
      : .minuteSecond(padMinuteToLength: 2)
    return Duration.seconds(seconds).formatted(.time(pattern: pattern))
  }
}
