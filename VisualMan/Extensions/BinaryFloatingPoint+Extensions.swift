//
//  BinaryFloatingPoint+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/20/25.
//

import Foundation

extension BinaryFloatingPoint {
  func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = style
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: TimeInterval(self)) ?? ""
  }
}
