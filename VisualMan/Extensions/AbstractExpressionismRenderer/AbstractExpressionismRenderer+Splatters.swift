//
//  AbstractExpressionismRenderer+Splatters.swift
//  VisualMan
//
//  Created by on 5/18/26.
//

#if !targetEnvironment(simulator)
import Metal

extension AbstractExpressionismRenderer {
  private func splatterPosition(focus: SIMD2<Float>) -> (Float, Float) {
    let isOutlier = nextSeed() < 0.60
    if isOutlier {
      return ((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    }
    return (focus.x + (nextSeed() - 0.5) * 1.40,
            focus.y + (nextSeed() - 0.5) * 1.50)
  }

  private func splatterSizeAndOpacity(high: Float) -> (radius: Float, opacity: Float) {
    let sizeRoll = nextSeed()
    let radius: Float
    let opacityBase: Float
    if sizeRoll < 0.12 {
      radius = 0.0015 + nextSeed() * 0.003
      opacityBase = 0.98
    } else if sizeRoll < 0.25 {
      radius = 0.005 + nextSeed() * 0.008
      opacityBase = 0.95
    } else if sizeRoll < 0.55 {
      radius = 0.014 + nextSeed() * 0.016
      opacityBase = 0.93
    } else if sizeRoll < 0.85 {
      radius = 0.028 + nextSeed() * 0.018
      opacityBase = 0.92
    } else {
      radius = 0.044 + nextSeed() * 0.024
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
    guard high > 0.05, (wallClock - lastSplatterTime) > 0.9, strokes.count < Self.maxStrokesPerFrame else { return }
    lastSplatterTime = wallClock
    let count: Int
    if high > 0.45 {
      count = 3
    } else if high > 0.25 {
      count = 2
    } else {
      count = 1
    }
    for _ in 0..<count where strokes.count < Self.maxStrokesPerFrame {
      let focus = splatterFocus()
      let burstShapeRoll = nextSeed()
      let burstTypeRoll  = nextSeed()
      let mainStroke = makeSplatterStroke(high: high, focus: focus,
                                            burstShapeRoll: burstShapeRoll,
                                            burstTypeRoll: burstTypeRoll)
      let mainRadius = mainStroke.posAngle.w
      strokes.append(mainStroke)
      
      let densityWeight: Float
      if burstTypeRoll < 0.10 {
        densityWeight = 0.10
      } else if burstTypeRoll < 0.30 {
        densityWeight = 0.30
      } else if burstTypeRoll < 0.70 {
        densityWeight = 0.80
      } else {
        densityWeight = 1.50
      }
      depositDensity(at: SIMD2(focus.x, focus.y), weight: densityWeight)

      if mainRadius > 0.012 && nextSeed() < 0.55 && strokes.count < Self.maxStrokesPerFrame {
        let satCount = (mainRadius > 0.030) ? Int(2 + nextSeed() * 2) : 1
        for _ in 0..<satCount where strokes.count < Self.maxStrokesPerFrame {
          let satAngle = nextSeed() * .pi * 2
          let satDist = mainRadius * (2.0 + nextSeed() * 4.0)
          let satX = focus.x + cos(satAngle) * satDist
          let satY = focus.y + sin(satAngle) * satDist
          let satRadius = 0.0010 + nextSeed() * 0.0025
          let bristleSeed = nextSeed() * 100
          let satTypeRoll = nextSeed()
          let color = mainStroke.color
          strokes.append(AbExStroke(
            posAngle: SIMD4(satX, satY, 0, satRadius),
            sizeOpacity: SIMD4(satTypeRoll, 0.85 + nextSeed() * 0.10,
                                 bristleSeed, 2),
            color: color,
            animation: SIMD4(0, 1, 0, 0)))
        }
      }
    }
  }
}

#endif
