//
//  SmoothedAudio.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

import Foundation

struct SmoothedAudio {
  var bass: Float = 0
  var mid: Float = 0
  var high: Float = 0
  var time: Float = 0

  private static let bassTau: Float = 0.012
  private static let midTau: Float = 0.020
  private static let highTau: Float = 0.008

  mutating func update(from levels: borrowing [1024 of Float], dt: Float) {
    let safeDt = max(dt, 1e-6)
    let bassAlpha = 1 - exp(-safeDt / Self.bassTau)
    let midAlpha = 1 - exp(-safeDt / Self.midTau)
    let highAlpha = 1 - exp(-safeDt / Self.highTau)
    bass += (levels.bassLevel - bass) * bassAlpha
    mid += (levels.midLevel - mid) * midAlpha
    high += (levels.highLevel - high) * highAlpha
    time += dt * (1.0 + bass * 0.5 + mid * 0.3)
  }
}
