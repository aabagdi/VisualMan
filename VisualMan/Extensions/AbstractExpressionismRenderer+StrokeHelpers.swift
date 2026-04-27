//
//  AbstractExpressionismRenderer+StrokeHelpers.swift
//  VisualMan
//
//  Created by on 4/25/26.
//

import Metal
import simd

extension AbstractExpressionismRenderer {
  nonisolated static func srgbToLinear(_ c: SIMD3<Float>) -> SIMD3<Float> {
    func f(_ x: Float) -> Float {
      x <= 0.04045 ? x / 12.92 : pow((x + 0.055) / 1.055, 2.4)
    }
    return SIMD3(f(c.x), f(c.y), f(c.z))
  }

  static let warmColors: [SIMD3<Float>] = [
    SIMD3(0.85, 0.15, 0.05), SIMD3(0.90, 0.55, 0.05),
    SIMD3(0.80, 0.60, 0.10), SIMD3(0.55, 0.25, 0.08),
    SIMD3(0.35, 0.15, 0.08), SIMD3(0.75, 0.05, 0.20),
  ].map(srgbToLinear)

  static let coolColors: [SIMD3<Float>] = [
    SIMD3(0.05, 0.10, 0.70), SIMD3(0.05, 0.35, 0.65),
    SIMD3(0.10, 0.40, 0.25), SIMD3(0.25, 0.10, 0.50),
    SIMD3(0.02, 0.20, 0.45), SIMD3(0.15, 0.55, 0.35),
  ].map(srgbToLinear)

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
    var baseHue = (time * 0.0042 + songSeed * 0.7)
      .truncatingRemainder(dividingBy: 1.0)
    if baseHue < 0 { baseHue += 1 }

    let energy = (slowEnvelope.x + slowEnvelope.y + slowEnvelope.z) / 3.0
    let dissonance = min(max(energy * 1.5, 0.05), 0.95)

    let r = nextSeed()
    let offset: Float
    if r < 0.60 {
      offset = (nextSeed() - 0.5) * 0.24 * (0.5 + dissonance * 0.5)
    } else if r < 0.88 {
      let direction: Float = (nextSeed() < 0.5) ? 1.0 : -1.0
      offset = direction * (0.42 + (nextSeed() - 0.5) * 0.16) * dissonance
    } else {
      offset = 0.5 + (nextSeed() - 0.5) * 0.10
    }

    var hue = (baseHue + offset).truncatingRemainder(dividingBy: 1.0)
    if hue < 0 { hue += 1 }

    let satBase: Float = 0.55 + dissonance * 0.20
    let sat = min(0.95, satBase + nextSeed() * 0.20)
    let val = 0.50 + nextSeed() * 0.40

    let rgbSrgb = Self.hsvToRgb(SIMD3(hue, sat, val))
    return Self.srgbToLinear(rgbSrgb)
  }

  nonisolated static func hsvToRgb(_ hsv: SIMD3<Float>) -> SIMD3<Float> {
    let h = hsv.x * 6.0
    let s = hsv.y
    let v = hsv.z
    let c = v * s
    let x = c * (1.0 - abs(h.truncatingRemainder(dividingBy: 2.0) - 1.0))
    let m = v - c
    let rgb: SIMD3<Float>
    switch Int(h) {
    case 0:  rgb = SIMD3(c, x, 0)
    case 1:  rgb = SIMD3(x, c, 0)
    case 2:  rgb = SIMD3(0, c, x)
    case 3:  rgb = SIMD3(0, x, c)
    case 4:  rgb = SIMD3(x, 0, c)
    default: rgb = SIMD3(c, 0, x)
    }
    return rgb + SIMD3<Float>(repeating: m)
  }

  private static let permanentDurabilityBase: Float = 0.80
  private static let permanentDurabilityJitter: Float = 0.15
  private static let stickyDurabilityBase: Float = 0.35
  private static let stickyDurabilityJitter: Float = 0.30

  func pickDurability(permanentChance: Float, stickyChance: Float) -> Float {
    assert(permanentChance + stickyChance <= 1,
           "permanentChance + stickyChance must be <= 1; got \(permanentChance + stickyChance)")
    let r = nextSeed()
    if r < permanentChance {
      return Self.permanentDurabilityBase + nextSeed() * Self.permanentDurabilityJitter
    } else if r < permanentChance + stickyChance {
      return Self.stickyDurabilityBase + nextSeed() * Self.stickyDurabilityJitter
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

  private func flowIndex(at p: SIMD2<Float>) -> Int {
    let n = Float(Self.flowGridSize)
    let u = max(0, min(0.999, p.x + 0.5))
    let v = max(0, min(0.999, p.y + 0.5))
    let ix = Int(u * n)
    let iy = Int(v * n)
    return iy * Self.flowGridSize + ix
  }

  func depositFlow(at p: SIMD2<Float>, angle: Float, weight: Float = 1.0) {
    let n = Self.flowGridSize
    let nf = Float(n)
    let cu = (p.x + 0.5) * nf
    let cv = (p.y + 0.5) * nf
    let dir = SIMD2<Float>(cos(angle), sin(angle))
    let w = weight * Self.flowDepositWeight
    let cx = Int(cu)
    let cy = Int(cv)
    for dy in -1...1 {
      for dx in -1...1 {
        let gx = cx + dx
        let gy = cy + dy
        guard gx >= 0, gx < n, gy >= 0, gy < n else { continue }
        let dist2 = Float(dx * dx + dy * dy)
        let falloff = exp(-dist2 * 0.7)
        flowField[gy * n + gx] += dir * (w * falloff)
      }
    }
  }

  func decayFlow() {
    for i in 0..<flowField.count {
      flowField[i] *= Self.flowDecayPerFrame
    }
  }

  private func densityIndex(at p: SIMD2<Float>) -> Int {
    let n = Float(Self.densityGridSize)
    let u = max(0, min(0.999, p.x + 0.5))
    let v = max(0, min(0.999, p.y + 0.5))
    let ix = Int(u * n)
    let iy = Int(v * n)
    return iy * Self.densityGridSize + ix
  }

  func depositDensity(at p: SIMD2<Float>, weight: Float = 1.0) {
    let n = Self.densityGridSize
    let nf = Float(n)
    let cu = (p.x + 0.5) * nf
    let cv = (p.y + 0.5) * nf
    let w = weight * Self.densityDepositWeight
    let cx = Int(cu)
    let cy = Int(cv)
    for dy in -1...1 {
      for dx in -1...1 {
        let gx = cx + dx
        let gy = cy + dy
        guard gx >= 0, gx < n, gy >= 0, gy < n else { continue }
        let dist2 = Float(dx * dx + dy * dy)
        let falloff = exp(-dist2 * 0.7)
        densityGrid[gy * n + gx] += w * falloff
      }
    }
  }

  func decayDensity() {
    for i in 0..<densityGrid.count {
      densityGrid[i] *= Self.densityDecayPerFrame
    }
  }

  func sampleDensity(at p: SIMD2<Float>) -> Float {
    return densityGrid[densityIndex(at: p)]
  }

  func applyDensityBias(at suggested: SIMD2<Float>,
                        dispersion: Float = 0.30) -> SIMD2<Float> {
    let dHere = sampleDensity(at: suggested)
    if dHere < 0.4 { return suggested }

    var best = suggested
    var bestD = dHere
    for _ in 0..<4 {
      let dx = (nextSeed() * 2 - 1) * dispersion
      let dy = (nextSeed() * 2 - 1) * dispersion
      let candidate = SIMD2(
        max(-0.50, min(0.50, suggested.x + dx)),
        max(-0.55, min(0.55, suggested.y + dy)))
      let d = sampleDensity(at: candidate)
      if d < bestD {
        best = candidate
        bestD = d
      }
    }

    let biasStrength = min(Self.densityMaxBias,
                           (dHere - 0.4) / 2.0)
    return suggested + (best - suggested) * biasStrength
  }

  private func sampleFlow(at p: SIMD2<Float>) -> SIMD2<Float> {
    return flowField[flowIndex(at: p)]
  }

  func localStrokeAngle(at p: SIMD2<Float>) -> Float {
    let scale: Float = 1.6
    let phase = songSeed * 3.7
    let fx = sin(p.x * scale + phase)
           + 0.5 * cos(p.y * scale * 1.3 + phase * 1.7)
    let fy = cos(p.x * scale * 1.1 + phase * 0.9)
           + 0.5 * sin(p.y * scale + phase * 1.3)
    let analytic = SIMD2<Float>(fx, fy)

    let flow = sampleFlow(at: p)
    let flowMag = simd_length(flow)

    if flowMag < 0.05 {
      return atan2(analytic.y, analytic.x)
    }

    let blend = min(flowMag / 2.0, Self.flowMaxBlend)
    let analyticDir = simd_normalize(analytic)
    let flowDir = flow / flowMag
    let blended = analyticDir * (1 - blend) + flowDir * blend
    return atan2(blended.y, blended.x)
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
