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
  func asTimeString() -> String {
    _positionalFormatter.string(from: TimeInterval(self)) ?? ""
  }
}
