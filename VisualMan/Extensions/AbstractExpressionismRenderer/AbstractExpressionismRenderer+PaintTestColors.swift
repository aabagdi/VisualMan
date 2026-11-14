//
//  AbstractExpressionismRenderer+PaintTestColors.swift
//  VisualMan
//
//  Created on 11/12/26.
//

#if DEBUG && !targetEnvironment(simulator)
import Foundation
import simd

extension AbstractExpressionismRenderer {
  private struct ColorPair {
    let first: TestPigment
    let second: TestPigment
    let expect: String
  }

  private static let colorPairs: [ColorPair] = [
    ColorPair(first: .cadmiumYellow, second: .ultramarineBlue, expect: "GREEN"),
    ColorPair(first: .cadmiumYellow, second: .cadmiumRed, expect: "ORANGE"),
    ColorPair(first: .cadmiumRed, second: .cobaltBlue, expect: "MAROON, not purple"),
    ColorPair(first: .quinacridoneMagenta, second: .cobaltBlue, expect: "PURPLE"),
    ColorPair(first: .cadmiumRed, second: .phthaloGreen, expect: "BROWN"),
    ColorPair(first: .cadmiumOrange, second: .cobaltBlue, expect: "muted OLIVE-BROWN"),
    ColorPair(first: .hansaYellow, second: .phthaloBlue, expect: "deep GREEN"),
    ColorPair(first: .ultramarineBlue, second: .titaniumWhite, expect: "LIGHT BLUE, not grey"),
  ]

  private static let colorRowTop: Float = -0.30
  private static let colorRowSpacing: Float = 0.09
  private static let colorRowSeconds: Float = 2.0
  private static let colorWashOpacity: Float = 0.9

  private static var builtColorScript: [PaintTestEvent] = []

  static func colorScript(mixes: [SIMD3<Float>]) -> [PaintTestEvent] {
    if builtColorScript.isEmpty { builtColorScript = makeColorScript(mixes: mixes) }
    return builtColorScript
  }

  static func testSwatch(at pos: SIMD2<Float>, radius: Float,
                         color c: SIMD3<Float>, seed: Float) -> AbExStroke {
    AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, 0, radius),
      sizeOpacity: SIMD4(0.50, 0.98, seed, 2),
      color: SIMD4(c.x, c.y, c.z, 2),
      animation: SIMD4(0, 1, 0, 0))
  }

  private static func colorLadder(_ pair: ColorPair,
                                  mixes: [SIMD3<Float>]) -> [(percent: Int, color: SIMD3<Float>)] {
    let a = pair.first.rawValue, b = pair.second.rawValue
    var ladder = [(percent: 0, color: pair.first.linearRgb)]
    if mixes.count == paletteMixCount {
      for (k, share) in paletteMixShares.enumerated() {
        ladder.append((Int((share * 100).rounded()), mixes[paletteMixIndex(a, b, k)]))
      }
      for (k, share) in paletteMixShares.enumerated().reversed() where share < 0.5 {
        ladder.append((Int(((1 - share) * 100).rounded()), mixes[paletteMixIndex(b, a, k)]))
      }
    }
    ladder.append((100, pair.second.linearRgb))
    return ladder
  }

  private static func makeColorScript(mixes: [SIMD3<Float>]) -> [PaintTestEvent] {
    var script = [PaintTestEvent]()
    for (row, pair) in colorPairs.enumerated() {
      let y = colorRowTop + Float(row) * colorRowSpacing
      let start = 0.5 + Float(row) * colorRowSeconds
      let seed = Float(500 + row * 10)
      let names = "\(mixboxPigments[pair.first.rawValue].name) → \(mixboxPigments[pair.second.rawValue].name)"

      let ladder = colorLadder(pair, mixes: mixes)
      let percents = ladder.map { String($0.percent) }.joined(separator: "/")
      let laid = ladder.count > 2
        ? "Row \(row + 1)  \(names): dots are Mixbox at \(percents)%"
        : "Row \(row + 1)  \(names): NO PRE-MIX TABLE, pure dots only"
      script.append(PaintTestEvent(time: start, label: laid, strokes: ladder.enumerated().map { i, step in
        testSwatch(at: SIMD2(-0.19 + Float(i) * 0.027, y), radius: 0.0115,
                   color: step.color, seed: seed + Float(i))
      }))
      script.append(PaintTestEvent(time: start + 0.1, label: laid, strokes: [
        testWash(at: SIMD2(0.04, y), angle: 0, halfLen: 0.042, halfWidth: 0.030,
                 opacity: colorWashOpacity, pigment: pair.first, seed: seed + 8),
        testGestural(at: SIMD2(0.165, y), angle: 0, halfLen: 0.033, halfWidth: 0.011,
                     pigment: pair.first, load: .medium, variant: row * 2),
      ]))
      let inset = pair.second == .titaniumWhite
      script.append(PaintTestEvent(
        time: start + 1.0,
        label: "Row \(row + 1)  wash overlap and wet brush crossing should read \(pair.expect), like the middle dots",
        strokes: [
          testWash(at: SIMD2(inset ? 0.045 : 0.08, y), angle: 0,
                   halfLen: inset ? 0.024 : 0.042, halfWidth: inset ? 0.017 : 0.030,
                   opacity: colorWashOpacity, pigment: pair.second, seed: seed + 9),
          testGestural(at: SIMD2(0.165, y), angle: 1.3, halfLen: 0.033, halfWidth: 0.011,
                       pigment: pair.second, load: .medium, variant: row * 2 + 1),
        ]))
    }
    let done = 0.5 + Float(colorPairs.count) * colorRowSeconds + 1.5
    script.append(PaintTestEvent(
      time: done,
      label: "Done. Wash overlaps sit near the 50% dot, crossings near 35%; restarts at 30 s",
      strokes: []))
    return script
  }
}

#endif
