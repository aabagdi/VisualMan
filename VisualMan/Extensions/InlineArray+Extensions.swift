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

extension InlineArray where Element: BitwiseCopyable {
  nonisolated mutating func withUnsafeElementPointer<Result>(
    _ body: (UnsafeMutablePointer<Element>) throws -> Result
  ) rethrows -> Result {
    try withUnsafeMutablePointer(to: &self) { ptr in
      try body(UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: Element.self))
    }
  }
}
