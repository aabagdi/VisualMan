//
//  BinaryFloatingPoint+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/20/25.
//

import Foundation

private let _positionalFormatter: DateComponentsFormatter = {
  let formatter = DateComponentsFormatter()
  formatter.allowedUnits = [.minute, .second]
  formatter.unitsStyle = .positional
  formatter.zeroFormattingBehavior = .pad
  return formatter
}()

extension BinaryFloatingPoint {
  func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
    if style == .positional {
      return _positionalFormatter.string(from: TimeInterval(self)) ?? ""
    }
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = style
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: TimeInterval(self)) ?? ""
  }
}
