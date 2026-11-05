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

  var bandTime: SIMD3<Float> = .zero

  private static let attackTau = SIMD3<Float>(0.015, 0.020, 0.010)
  private static let releaseTau = SIMD3<Float>(0.120, 0.150, 0.090)

  mutating func update(from levels: borrowing [1024 of Float], dt: Float) {
    let safeDt = max(dt, 1e-6)
    let input = SIMD3<Float>(levels.bassLevel, levels.midLevel, levels.highLevel)
    var current = SIMD3<Float>(bass, mid, high)
    for i in 0..<3 {
      let tau = input[i] > current[i] ? Self.attackTau[i] : Self.releaseTau[i]
      current[i] += (input[i] - current[i]) * (1 - exp(-safeDt / tau))
    }
    bass = current.x
    mid = current.y
    high = current.z
    time += dt * (1.0 + bass * 0.5 + mid * 0.3)
    bandTime += current * dt
  }
}
