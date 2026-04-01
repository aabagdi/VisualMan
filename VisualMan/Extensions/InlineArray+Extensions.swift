//
//  InlineArray+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/10/26.
//

import Foundation

extension InlineArray {
  func enumerated() -> [(Int, Self.Element)] {
    indices.lazy.map { ($0, self[$0]) }
  }
}

extension InlineArray: @retroactive Equatable where Element: Equatable {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    (0..<Self.count).allSatisfy { lhs[$0] == rhs[$0] }
  }
}

extension InlineArray<1024, Float> {
  var bassLevel: Float {
    let bassRange = 1..<10
    var bassResult: Float = 0.0
    for i in bassRange { bassResult += self[i] }
    return bassResult / Float(bassRange.count)
  }
  
  var midLevel: Float {
    let midRange = 10..<50
    var midResult: Float = 0.0
    var midMax: Float = 0.0
    for i in midRange {
      let currentLevel = self[i]
      midMax = max(midMax, currentLevel)
      midResult += currentLevel
    }
    let midAvg = midResult / Float(midRange.count)
    return midAvg * 0.5 + midMax * 0.5
  }
  
  var highLevel: Float {
    let highRange = 50..<150
    var highResult: Float = 0.0
    var highMax: Float = 0.0
    for i in highRange {
      let currentLevel = self[i]
      highMax = max(highMax, currentLevel)
      highResult += currentLevel
    }
    let highAvg = highResult / Float(highRange.count)
    return highMax * 0.7 + highAvg * 0.3
  }
}

extension InlineArray where Element: BitwiseCopyable {
  nonisolated mutating func withUnsafeElementPointer<Result>(
    _ body: (UnsafeMutablePointer<Element>) throws -> Result
  ) rethrows -> Result {
    try withUnsafeMutablePointer(to: &self) { ptr in
      try body(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Element.self))
    }
  }
}
