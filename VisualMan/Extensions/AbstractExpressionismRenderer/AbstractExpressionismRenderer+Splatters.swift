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
    // Spread splatters across the canvas more. Previously 35% outliers
    // and the rest tight-clustered around the slow-drifting focus,
    // which produced visible clusters when focus stayed in one region.
    // Now 60% outliers (full-canvas random) and the remaining 40%
    // spread very widely around focus (1.4 vs 0.75 spread). The
    // composition still has some clustering bias toward the focus, but
    // it's gentle rather than concentrated.
    let isOutlier = nextSeed() < 0.60
    if isOutlier {
      return ((nextSeed() - 0.5) * 1.05, (nextSeed() - 0.5) * 1.10)
    }
    return (focus.x + (nextSeed() - 0.5) * 1.40,
            focus.y + (nextSeed() - 0.5) * 1.50)
  }

  private func splatterSizeAndOpacity(high: Float) -> (radius: Float, opacity: Float) {
    // Size distribution rebalanced to make medium/large splats more
    // visible and tiny dots less dominant. Previously 40% of splats
    // were in the 0.0015-0.013 range (tiny dots) which read as noise.
    // Now only 20% tiny, with the bulk shifted to medium (0.012-0.030)
    // where splat shape and impasto are clearly visible.
    let sizeRoll = nextSeed()
    let radius: Float
    let opacityBase: Float
    if sizeRoll < 0.12 {
      // Tiny spray dots - still present for variety/satellite feel
      radius = 0.0015 + nextSeed() * 0.003
      opacityBase = 0.98
    } else if sizeRoll < 0.25 {
      // Small splats
      radius = 0.005 + nextSeed() * 0.008
      opacityBase = 0.95
    } else if sizeRoll < 0.55 {
      // Medium - the bulk of splats now
      radius = 0.014 + nextSeed() * 0.016
      opacityBase = 0.93
    } else if sizeRoll < 0.85 {
      // Large splats
      radius = 0.028 + nextSeed() * 0.018
      opacityBase = 0.92
    } else {
      // Heavy splats - rare but striking
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
    // Splatter rate: was 1.2s gate, dropped to 0.7s so splats appear
    // more frequently across the canvas. They're cheap to deposit and
    // create the foundation of paint that knives target.
    guard high > 0.05, (wallClock - lastSplatterTime) > 0.9, strokes.count < Self.maxStrokesPerFrame else { return }
    lastSplatterTime = wallClock
    // Splat count scales with audio energy. Low energy: 1 splat.
    // Mid energy: 2 splats. High peaks: 3 splats. Provides a clear
    // audio-reactive feel without overwhelming density.
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
      // Density weighted by impasto bucket. Heavy impasto splats deposit
      // more density to the targeting field, making them more attractive
      // to knives via applyDensitySeek. The mapping mirrors the shader's
      // bucket thresholds:
      //   - typeRoll < 0.10 (flat): 0.10 — barely targetable
      //   - typeRoll < 0.30 (light): 0.30
      //   - typeRoll < 0.70 (medium): 0.80
      //   - typeRoll ≥ 0.70 (heavy): 1.50 — strongly attracts knives
      // Knives will preferentially seek heavy splats first, smear them
      // (consuming density), then move to the next-highest target.
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
          // sizeOpacity.x must be a typeRoll [0,1] - the shader reads
          // this as the impasto-bucket selector. Was previously
          // satRadius (tiny number ~0.001), which always landed in
          // the flat bucket. Now a fresh random so satellites can
          // be flat or have body, matching the main splat's variation.
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
