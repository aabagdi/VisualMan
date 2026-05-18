//
//  AbstractExpressionismRenderer+StrokeHelpers.swift
//  VisualMan
//
//  Created by on 4/25/26.
//

import Metal
import simd

extension AbstractExpressionismRenderer {
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

  func pickCurvature(zeroChance: Float, midThreshold: Float,
                     ampBase: Float, ampJitter: Float) -> Float {
    let curveRoll = nextSeed()
    if curveRoll < zeroChance { return 0 }
    let amp = ampBase + nextSeed() * ampJitter
    let dir: Float = nextSeed() < 0.5 ? 1 : -1
    if curveRoll < midThreshold { return amp * dir }
    return (1.0 + amp) * dir
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

  func sampleGesturedStroke(suggestedPos: SIMD2<Float>,
                            suggestedAngle: Float,
                            continueProb: Float = 0.70)
                          -> (pos: SIMD2<Float>, angle: Float) {
    let timedOut = (wallClock - currentGestureStarted)
                   > Self.gestureTimeoutSeconds
    let active = currentGestureRemaining > 0 && !timedOut

    if active && nextSeed() < continueProb {
      currentGestureRemaining -= 1
      let along = (nextSeed() - 0.5) * 2.0 * currentGestureSpan
      let perp  = (nextSeed() - 0.5) * 0.08
      let cs = cos(currentGestureAngle)
      let sn = sin(currentGestureAngle)
      let offset = SIMD2(along * cs - perp * sn,
                         along * sn + perp * cs)
      let pos = currentGestureCenter + offset
      let jitter = (nextSeed() - 0.5) * (10.0 * .pi / 180.0)
      return (pos: pos, angle: currentGestureAngle + jitter)
    }

    currentGestureRemaining = 1 + Int(nextSeed() * 4.0)
    currentGestureAngle = suggestedAngle
    currentGestureCenter = suggestedPos
    currentGestureStarted = wallClock
    currentGestureSpan = 0.18 + nextSeed() * 0.20
    return (pos: suggestedPos, angle: suggestedAngle)
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

  func isInAttentionZone(_ p: SIMD2<Float>) -> Bool {
    return attentionStrength(at: p) > 0.5
  }

  func attentionStrength(at p: SIMD2<Float>) -> Float {
    let t = wallClock * 0.012
    let p1 = SIMD2(p.x * 1.5 + t, p.y * 1.5 + t * 0.7)
    let p2 = SIMD2(p.x * 3.2 - t * 0.4, p.y * 3.2 + t * 0.3)
    let n1 = simplexLike(p1)
    let n2 = simplexLike(p2) * 0.4
    let combined = n1 + n2
    return min(1.0, max(0.0, combined * 0.5 + 0.55))
  }

  private func simplexLike(_ p: SIMD2<Float>) -> Float {
    let i = SIMD2(floor(p.x), floor(p.y))
    let f = p - i
    let u = f * f * (SIMD2<Float>(repeating: 3.0) - 2.0 * f)
    let h00 = hashCell(i + SIMD2(0, 0))
    let h10 = hashCell(i + SIMD2(1, 0))
    let h01 = hashCell(i + SIMD2(0, 1))
    let h11 = hashCell(i + SIMD2(1, 1))
    let mix0 = h00 + (h10 - h00) * u.x
    let mix1 = h01 + (h11 - h01) * u.x
    return (mix0 + (mix1 - mix0) * u.y) * 2.0 - 1.0
  }

  private func hashCell(_ i: SIMD2<Float>) -> Float {
    var h = i.x * 12.9898 + i.y * 78.233
    h = sin(h) * 43758.5453
    return h - floor(h)
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
