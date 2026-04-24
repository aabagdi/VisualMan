//
//  AbstractExpressionismRenderer+Strokes.swift
//  VisualMan
//
//  Created by on 4/24/26.
//

import Metal

extension AbstractExpressionismRenderer {
  private static let warmColors: [SIMD3<Float>] = [
    SIMD3(0.85, 0.15, 0.05), SIMD3(0.90, 0.55, 0.05),
    SIMD3(0.80, 0.60, 0.10), SIMD3(0.55, 0.25, 0.08),
    SIMD3(0.35, 0.15, 0.08), SIMD3(0.75, 0.05, 0.20),
  ]

  private static let coolColors: [SIMD3<Float>] = [
    SIMD3(0.05, 0.10, 0.70), SIMD3(0.05, 0.35, 0.65),
    SIMD3(0.10, 0.40, 0.25), SIMD3(0.25, 0.10, 0.50),
    SIMD3(0.02, 0.20, 0.45), SIMD3(0.15, 0.55, 0.35),
  ]

  private static let compositionAnchors: [SIMD2<Float>] = [
    SIMD2(-0.22, 0.24),
    SIMD2( 0.28, -0.20),
    SIMD2( 0.08, 0.30),
    SIMD2(-0.24, -0.12),
  ]

  private func nextSeed() -> Float {
    strokeSeed &+= 1
    let x = strokeSeed &* 2654435769
    return Float(x) / Float(UInt32.max)
  }

  private func pickColor(warm: Bool) -> SIMD3<Float> {
    let palette = warm ? Self.warmColors : Self.coolColors
    let r = nextSeed()
    let idx = Int(r * Float(palette.count)) % palette.count
    var color = palette[idx]
    let variation = SIMD3<Float>(nextSeed() - 0.5, nextSeed() - 0.5, nextSeed() - 0.5) * 0.1
    color = pointwiseMin(pointwiseMax(color + variation, .zero), SIMD3(repeating: 1))
    return color
  }

  private func pickColorBiased() -> SIMD3<Float> {
    let drifted = 0.5 + sin(time * 0.018 + songSeed * 2.1) * 0.32
    return pickColor(warm: nextSeed() > drifted)
  }

  private func pickDurability(permanentChance: Float, stickyChance: Float) -> Float {
    let r = nextSeed()
    if r < permanentChance {
      return 0.80 + nextSeed() * 0.15
    } else if r < permanentChance + stickyChance {
      return 0.35 + nextSeed() * 0.30
    } else {
      return 0
    }
  }

  private func packColorW(shape: Float, durability: Float) -> Float {
    return shape + durability
  }

  private func compositionFocus() -> SIMD2<Float> {
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

  private func dominantAngle() -> Float {
    return time * 0.045 + songSeed * 1.2
  }

  private func splatterFocus() -> SIMD2<Float> {
    let t = time + songSeed * 11.9
    let fx = sin(t * 0.45 + songSeed * 3.1) * 0.32
           + cos(t * 1.10 + songSeed * 5.7) * 0.14
    let fy = cos(t * 0.38 + songSeed * 2.3) * 0.38
           + sin(t * 0.95 + songSeed * 4.1) * 0.15
    return SIMD2(fx, fy)
  }

  private func appendBassTransientStrokes(to strokes: inout [AbExStroke],
                                          bass: Float, focus: SIMD2<Float>, spread: Float) {
    lastGesturalTime = wallClock
    let count = bass > 0.25 ? 3 : (bass > 0.10 ? 2 : 1)
    for _ in 0..<count where strokes.count < 8 {
      let isOutlier = nextSeed() < 0.22
      let x: Float
      let y: Float
      if isOutlier {
        x = (nextSeed() - 0.5) * 1.00
        y = (nextSeed() - 0.5) * 1.05
      } else {
        x = focus.x + (nextSeed() - 0.5) * 0.85 * spread
        y = focus.y + (nextSeed() - 0.5) * 0.95 * spread
      }
      let angle = nextSeed() * .pi * 2
      let halfLen = 0.14 + bass * 0.28 + nextSeed() * 0.10
      let halfWidth = 0.014 + bass * 0.022 + nextSeed() * 0.010
      let opacity = 0.85 + bass * 0.15
      let bristleSeed = nextSeed() * 100
      let color = pickColorBiased()
      let dur = pickDurability(permanentChance: 0.08, stickyChance: 0.22)
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, angle, halfLen),
        sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 0),
        color: SIMD4(color.x, color.y, color.z, packColorW(shape: 0, durability: dur))))
    }
  }

  private func appendGesturalStroke(to strokes: inout [AbExStroke],
                                    energy: Float, focus: SIMD2<Float>, spread: Float) {
    lastGesturalTime = wallClock
    let isOutlier = nextSeed() < 0.28
    let x: Float
    let y: Float
    if isOutlier {
      x = (nextSeed() - 0.5) * 1.00
      y = (nextSeed() - 0.5) * 1.05
    } else {
      x = focus.x + (nextSeed() - 0.5) * 0.88 * spread
      y = focus.y + (nextSeed() - 0.5) * 0.92 * spread
    }
    let dom = dominantAngle()
    let angle = (nextSeed() < 0.55)
      ? dom + (nextSeed() - 0.5) * 0.9
      : nextSeed() * .pi * 2
    let halfLen = 0.09 + energy * 0.18 + nextSeed() * 0.07
    let halfWidth = 0.011 + energy * 0.014 + nextSeed() * 0.007
    let opacity = 0.65 + energy * 0.25
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    let dur = pickDurability(permanentChance: 0.03, stickyChance: 0.15)
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 0),
      color: SIMD4(color.x, color.y, color.z, packColorW(shape: 0, durability: dur))))
  }

  private func appendRogueStroke(to strokes: inout [AbExStroke], energy: Float) {
    guard strokes.count < 8, nextSeed() < 0.06 else { return }

    let x = (nextSeed() - 0.5) * 1.05
    let y = (nextSeed() - 0.5) * 1.10
    let angle = nextSeed() * .pi * 2
    let typeRoll = nextSeed()
    let color = pickColorBiased()

    if typeRoll < 0.55 {
      let halfLen = 0.10 + nextSeed() * 0.22
      let halfWidth = 0.009 + nextSeed() * 0.010
      let opacity: Float = 0.70 + nextSeed() * 0.20
      let bristleSeed = nextSeed() * 100
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, angle, halfLen),
        sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 0),
        color: SIMD4(color.x, color.y, color.z, 0)))
    } else {
      let radius = 0.006 + nextSeed() * 0.014
      let opacity: Float = 0.85 + nextSeed() * 0.15
      let bristleSeed = nextSeed() * 100
      strokes.append(AbExStroke(
        posAngle: SIMD4(x, y, 0, radius),
        sizeOpacity: SIMD4(radius, opacity, bristleSeed, 2),
        color: SIMD4(color.x, color.y, color.z, 0)))
    }
  }

  private func appendWash(to strokes: inout [AbExStroke], mid: Float, focus: SIMD2<Float>) {
    guard mid > 0.04, (wallClock - lastWashTime) > 0.3, strokes.count < 8 else { return }
    lastWashTime = wallClock
    let x = focus.x * 0.6 + (nextSeed() - 0.5) * 1.00
    let y = focus.y * 0.6 + (nextSeed() - 0.5) * 1.05
    let angle = nextSeed() * .pi
    let concentrationRoll = nextSeed()
    let opacity: Float
    let sizeMult: Float
    if concentrationRoll < 0.08 {
      opacity  = 0.55 + mid * 0.35 + nextSeed() * 0.08
      sizeMult = 1.6 + nextSeed() * 0.35
    } else if concentrationRoll < 0.45 {
      opacity  = 0.14 + mid * 0.16 + nextSeed() * 0.06
      sizeMult = 1.0
    } else {
      opacity  = 0.06 + mid * 0.12 + nextSeed() * 0.04
      sizeMult = 0.85
    }
    let halfLen = (0.18 + mid * 0.25) * sizeMult
    let halfWidth = (0.12 + mid * 0.18) * sizeMult
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
      color: SIMD4(color.x, color.y, color.z, 0)))
  }

  private func appendAmbientWash(to strokes: inout [AbExStroke],
                                 energy: Float, focus: SIMD2<Float>) {
    guard energy > 0.01, strokes.count < 8, nextSeed() < 0.04 else { return }
    let x = focus.x + (nextSeed() - 0.5) * 0.95
    let y = focus.y + (nextSeed() - 0.5) * 1.00
    let angle = time * 0.1 + nextSeed() * .pi
    let halfLen = 0.20 + nextSeed() * 0.15
    let halfWidth = 0.14 + nextSeed() * 0.10
    let opacity: Float = 0.04 + energy * 0.05
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    strokes.append(AbExStroke(
      posAngle: SIMD4(x, y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, bristleSeed, 1),
      color: SIMD4(color.x, color.y, color.z, 0)))
  }

  private func splatterPosition(focus: SIMD2<Float>) -> (Float, Float) {
    let isOutlier = nextSeed() < 0.35
    if isOutlier {
      return ((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    }
    return (focus.x + (nextSeed() - 0.5) * 0.42,
            focus.y + (nextSeed() - 0.5) * 0.45)
  }

  private func splatterSizeAndOpacity(high: Float) -> (radius: Float, opacity: Float) {
    let sizeRoll = nextSeed()
    let radius: Float
    let opacityBase: Float
    if sizeRoll < 0.50 {
      radius = 0.003 + nextSeed() * 0.008
      opacityBase = 0.90
    } else if sizeRoll < 0.82 {
      radius = 0.012 + nextSeed() * 0.018
      opacityBase = 0.85
    } else if sizeRoll < 0.97 {
      radius = 0.032 + nextSeed() * 0.028
      opacityBase = 0.75
    } else {
      radius = 0.065 + nextSeed() * 0.045
      opacityBase = 0.68
    }
    return (radius, opacityBase + high * 0.12)
  }

  private func splatterShape(radius: Float) -> (variant: Float, angle: Float) {
    let shapeRoll = nextSeed()
    if radius < 0.012 {
      return (shapeRoll < 0.85 ? 2.0 : 0.0, 0)
    } else if shapeRoll < 0.22 {
      let dom = dominantAngle()
      let angle = (nextSeed() < 0.60)
        ? dom + (nextSeed() - 0.5) * 0.7
        : nextSeed() * .pi * 2
      return (1.0, angle)
    } else if shapeRoll < 0.50 {
      return (2.0, 0)
    } else {
      return (0.0, 0)
    }
  }

  private func makeSplatterStroke(high: Float, focus: SIMD2<Float>) -> AbExStroke {
    let (x, y) = splatterPosition(focus: focus)
    let (radius, opacity) = splatterSizeAndOpacity(high: high)
    let (shapeVariant, angle) = splatterShape(radius: radius)
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    let dur = pickDurability(permanentChance: 0.12, stickyChance: 0.28)
    return AbExStroke(
      posAngle: SIMD4(x, y, angle, radius),
      sizeOpacity: SIMD4(radius, opacity, bristleSeed, 2),
      color: SIMD4(color.x, color.y, color.z, packColorW(shape: shapeVariant, durability: dur)))
  }

  private func appendSplatters(to strokes: inout [AbExStroke], high: Float) {
    guard high > 0.03, (wallClock - lastSplatterTime) > 0.08, strokes.count < 8 else { return }
    lastSplatterTime = wallClock
    let focus = splatterFocus()
    let count = high > 0.30 ? 3 : (high > 0.15 ? 2 : 1)
    for _ in 0..<count where strokes.count < 8 {
      strokes.append(makeSplatterStroke(high: high, focus: focus))
    }
  }

  func generateStrokes(audio: SIMD3<Float>) -> [AbExStroke] {
    var strokes = [AbExStroke]()
    if resumeSuppressionRemaining > 0 { return strokes }

    let bass = audio.x, mid = audio.y, high = audio.z
    let energy = (bass + mid + high) / 3.0
    let focus = compositionFocus()
    let spread: Float = 0.85 + energy * 0.5

    let bassTransient = bass > smoothedBass * 1.15 && bass > 0.025
    let transientFired = bassTransient
                      && (wallClock - lastGesturalTime) > 0.10
                      && strokes.count < 8

    if transientFired {
      appendBassTransientStrokes(to: &strokes, bass: bass, focus: focus, spread: spread)
    }
    if !transientFired
        && energy > 0.03
        && (wallClock - lastGesturalTime) > 0.15
        && strokes.count < 8
        && nextSeed() < 0.72 {
      appendGesturalStroke(to: &strokes, energy: energy, focus: focus, spread: spread)
    }
    appendWash(to: &strokes, mid: mid, focus: focus)
    appendSplatters(to: &strokes, high: high)
    appendAmbientWash(to: &strokes, energy: energy, focus: focus)
    appendRogueStroke(to: &strokes, energy: energy)

    return strokes
  }
}
