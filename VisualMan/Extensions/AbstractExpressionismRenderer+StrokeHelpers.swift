//
//  AbstractExpressionismRenderer+StrokeHelpers.swift
//  VisualMan
//
//  Created by on 4/25/26.
//

import Metal

extension AbstractExpressionismRenderer {
  static let warmColors: [SIMD3<Float>] = [
    SIMD3(0.85, 0.15, 0.05), SIMD3(0.90, 0.55, 0.05),
    SIMD3(0.80, 0.60, 0.10), SIMD3(0.55, 0.25, 0.08),
    SIMD3(0.35, 0.15, 0.08), SIMD3(0.75, 0.05, 0.20),
  ]

  static let coolColors: [SIMD3<Float>] = [
    SIMD3(0.05, 0.10, 0.70), SIMD3(0.05, 0.35, 0.65),
    SIMD3(0.10, 0.40, 0.25), SIMD3(0.25, 0.10, 0.50),
    SIMD3(0.02, 0.20, 0.45), SIMD3(0.15, 0.55, 0.35),
  ]

  static let compositionAnchors: [SIMD2<Float>] = [
    SIMD2(-0.22, 0.24),
    SIMD2( 0.28, -0.20),
    SIMD2( 0.08, 0.30),
    SIMD2(-0.24, -0.12),
  ]

  func nextSeed() -> Float {
    strokeSeed &+= 1
    let x = strokeSeed &* 2654435769
    return Float(x) / Float(UInt32.max)
  }

  func pickColor(warm: Bool) -> SIMD3<Float> {
    let palette = warm ? Self.warmColors : Self.coolColors
    let r = nextSeed()
    let idx = Int(r * Float(palette.count)) % palette.count
    var color = palette[idx]
    let variation = SIMD3<Float>(nextSeed() - 0.5, nextSeed() - 0.5, nextSeed() - 0.5) * 0.1
    color = pointwiseMin(pointwiseMax(color + variation, .zero), SIMD3(repeating: 1))
    return color
  }

  func pickColorBiased() -> SIMD3<Float> {
    let drifted = 0.5 + sin(time * 0.018 + songSeed * 2.1) * 0.32
    return pickColor(warm: nextSeed() > drifted)
  }

  func pickDurability(permanentChance: Float, stickyChance: Float) -> Float {
    let r = nextSeed()
    if r < permanentChance {
      return 0.80 + nextSeed() * 0.15
    } else if r < permanentChance + stickyChance {
      return 0.35 + nextSeed() * 0.30
    } else {
      return 0
    }
  }

  func packColorW(shape: Float, durability: Float) -> Float {
    return shape + durability
  }

  func compositionFocus() -> SIMD2<Float> {
    let t = time * 0.06 + songSeed * 7.3
    let anchors = Self.compositionAnchors
    let cycle = Float(anchors.count)
    let phase = t.truncatingRemainder(dividingBy: cycle)
    let i0 = Int(phase) % anchors.count
    let i1 = (i0 + 1) % anchors.count
    let f = phase - Float(i0)
    let blend = f * f * (3 - 2 * f)

    let a = anchors[i0]
    let b = anchors[i1]
    let lerped = a * (1 - blend) + b * blend

    let jitterX = sin(t * 3.7 + songSeed * 1.7) * 0.04
    let jitterY = cos(t * 4.1 + songSeed * 2.3) * 0.04

    return lerped + SIMD2(jitterX, jitterY)
  }

  func dominantAngle() -> Float {
    return time * 0.045 + songSeed * 1.2
  }

  func localStrokeAngle(at p: SIMD2<Float>) -> Float {
    let scale: Float = 1.6
    let phase = songSeed * 3.7
    let fx = sin(p.x * scale + phase)
           + 0.5 * cos(p.y * scale * 1.3 + phase * 1.7)
    let fy = cos(p.x * scale * 1.1 + phase * 0.9)
           + 0.5 * sin(p.y * scale + phase * 1.3)
    return atan2(fy, fx)
  }

  func splatterFocus() -> SIMD2<Float> {
    let t = time + songSeed * 11.9
    let fx = sin(t * 0.45 + songSeed * 3.1) * 0.32
           + cos(t * 1.10 + songSeed * 5.7) * 0.14
    let fy = cos(t * 0.38 + songSeed * 2.3) * 0.38
           + sin(t * 0.95 + songSeed * 4.1) * 0.15
    return SIMD2(fx, fy)
  }

  func trailHash(_ a: UInt32, _ b: UInt32) -> Float {
    var x = a &+ b &* 1664525
    x ^= x &>> 16
    x = x &* 2246822507
    x ^= x &>> 13
    x = x &* 3266489917
    x ^= x &>> 16
    return Float(x) / Float(UInt32.max)
  }
}
