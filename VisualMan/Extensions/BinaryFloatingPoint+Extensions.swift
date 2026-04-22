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

private let _abbreviatedFormatter: DateComponentsFormatter = {
  let formatter = DateComponentsFormatter()
  formatter.allowedUnits = [.minute, .second]
  formatter.unitsStyle = .abbreviated
  formatter.zeroFormattingBehavior = .pad
  return formatter
}()

private let _shortFormatter: DateComponentsFormatter = {
  let formatter = DateComponentsFormatter()
  formatter.allowedUnits = [.minute, .second]
  formatter.unitsStyle = .short
  formatter.zeroFormattingBehavior = .pad
  return formatter
}()

extension BinaryFloatingPoint {
  func asTimeString(style: DateComponentsFormatter.UnitsStyle) -> String {
    let formatter: DateComponentsFormatter = switch style {
    case .positional: _positionalFormatter
    case .abbreviated: _abbreviatedFormatter
    case .short: _shortFormatter
    default: {
      let f = DateComponentsFormatter()
      f.allowedUnits = [.minute, .second]
      f.unitsStyle = style
      f.zeroFormattingBehavior = .pad
      return f
    }()
    }
    return formatter.string(from: TimeInterval(self)) ?? ""
  }
}
