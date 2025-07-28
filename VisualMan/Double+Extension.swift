//
//  Double+Extension.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/27/25.
//

import Foundation

extension Double {
  func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = style
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: self) ?? ""
  }
}

extension BinaryFloatingPoint {
  func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
    let formatter = DateComponentsFormatter()
    formatter.allowedUnits = [.minute, .second]
    formatter.unitsStyle = style
    formatter.zeroFormattingBehavior = .pad
    return formatter.string(from: TimeInterval(self)) ?? "" //formatter.string(from: self) ?? ""
  }
}
