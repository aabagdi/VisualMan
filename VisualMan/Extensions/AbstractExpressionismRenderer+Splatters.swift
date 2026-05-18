//
//  AbstractExpressionismRenderer+Splatters.swift
//  VisualMan
//
//  Created by on 5/18/26.
//

import Metal

extension AbstractExpressionismRenderer {
  private func splatterPosition(focus: SIMD2<Float>) -> (Float, Float) {
    let isOutlier = nextSeed() < 0.35
    if isOutlier {
      return ((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    }
    return (focus.x + (nextSeed() - 0.5) * 0.75,
            focus.y + (nextSeed() - 0.5) * 0.80)
  }

  private func splatterSizeAndOpacity(high: Float) -> (radius: Float, opacity: Float) {
    let sizeRoll = nextSeed()
    let radius: Float
    let opacityBase: Float
    if sizeRoll < 0.20 {
      radius = 0.0015 + nextSeed() * 0.003
      opacityBase = 0.98
    } else if sizeRoll < 0.40 {
      radius = 0.005 + nextSeed() * 0.008
      opacityBase = 0.95
    } else if sizeRoll < 0.65 {
      radius = 0.012 + nextSeed() * 0.014
      opacityBase = 0.93
    } else if sizeRoll < 0.88 {
      radius = 0.025 + nextSeed() * 0.015
      opacityBase = 0.92
    } else {
      radius = 0.040 + nextSeed() * 0.020
      opacityBase = 0.88
    }
    return (radius, opacityBase + high * 0.06)
  }

  private func splatterShape(radius: Float, at p: SIMD2<Float>, burstRoll: Float) -> (variant: Float, angle: Float) {
    if radius < 0.012 {
      return (burstRoll < 0.50 ? 2.0 : 0.0, 0)
    } else if burstRoll < 0.15 {
      let local = localStrokeAngle(at: p)
      let angle = (nextSeed() < 0.60)
        ? local + (nextSeed() - 0.5) * 0.8
        : nextSeed() * .pi * 2
      return (1.0, angle)
    } else if burstRoll < 0.25 {
      return (2.0, 0)
    } else {
      return (0.0, 0)
    }
  }

  private func makeSplatterStroke(high: Float, focus: SIMD2<Float>,
                                  burstShapeRoll: Float, burstTypeRoll: Float) -> AbExStroke {
    let (x, y) = splatterPosition(focus: focus)
    let (radius, opacity) = splatterSizeAndOpacity(high: high)
    let (shapeVariant, angle) = splatterShape(radius: radius, at: SIMD2(x, y), burstRoll: burstShapeRoll)
    let bristleSeed = nextSeed() * 100
    let color = pickColorBiased()
    let dur = pickDurability(permanentChance: 0.12, stickyChance: 0.28)
    return AbExStroke(
      posAngle: SIMD4(x, y, angle, radius),
      sizeOpacity: SIMD4(burstTypeRoll, opacity, bristleSeed, 2),
      color: SIMD4(color.x, color.y, color.z, packColorW(shape: shapeVariant, durability: dur)),
      animation: SIMD4(0, 1, 0, 0))
  }

  func appendSplatters(to strokes: inout [AbExStroke], high: Float) {
    guard high > 0.05, (wallClock - lastSplatterTime) > 0.55, strokes.count < 12 else { return }
    lastSplatterTime = wallClock
    let count = high > 0.30 ? 2 : 1
    for _ in 0..<count where strokes.count < 12 {
      let focus = splatterFocus()
      let burstShapeRoll = nextSeed()
      let burstTypeRoll  = nextSeed()
      let mainStroke = makeSplatterStroke(high: high, focus: focus,
                                            burstShapeRoll: burstShapeRoll,
                                            burstTypeRoll: burstTypeRoll)
      let mainRadius = mainStroke.posAngle.w
      strokes.append(mainStroke)
      depositDensity(at: SIMD2(focus.x, focus.y), weight: 0.25)

      if mainRadius > 0.012 && nextSeed() < 0.55 && strokes.count < 12 {
        let satCount = (mainRadius > 0.030) ? Int(2 + nextSeed() * 2) : 1
        for _ in 0..<satCount where strokes.count < 12 {
          let satAngle = nextSeed() * .pi * 2
          let satDist = mainRadius * (2.0 + nextSeed() * 4.0)
          let satX = focus.x + cos(satAngle) * satDist
          let satY = focus.y + sin(satAngle) * satDist
          let satRadius = 0.0010 + nextSeed() * 0.0025
          let bristleSeed = nextSeed() * 100
          let color = mainStroke.color
          strokes.append(AbExStroke(
            posAngle: SIMD4(satX, satY, 0, satRadius),
            sizeOpacity: SIMD4(satRadius, 0.85 + nextSeed() * 0.10,
                                 bristleSeed, 2),
            color: color,
            animation: SIMD4(0, 1, 0, 0)))
        }
      }
    }
  }
}
