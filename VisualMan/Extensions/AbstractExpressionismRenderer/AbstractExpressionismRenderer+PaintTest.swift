//
//  AbstractExpressionismRenderer+PaintTest.swift
//  VisualMan
//
//  Created on 11/1/26.
//

#if !targetEnvironment(simulator)
import Foundation
import simd

extension AbstractExpressionismRenderer {
  enum PaintTestScenario {
    case mixing, cracks
  }

  static let paintTestScenario: PaintTestScenario? = {
    guard let raw = UserDefaults.standard.string(forKey: "AbExPaintTest")?
            .trimmingCharacters(in: .whitespaces).lowercased(),
          !raw.isEmpty, raw != "no", raw != "0", raw != "false" else { return nil }
    return raw == "cracks" ? .cracks : .mixing
  }()

  static let paintTestEnabled: Bool = paintTestScenario != nil

  static var paintTestLoopDuration: Float {
    paintTestScenario == .cracks ? 45 : 20
  }

  static var paintTestScript: [PaintTestEvent] {
    paintTestScenario == .cracks ? crackScript : mixingScript
  }

  static var paintTestDryMultiplier: Float {
    paintTestScenario == .cracks ? 3 : 1
  }

  struct PaintTestEvent {
    let time: Float
    let label: String
    let strokes: [AbExStroke]
  }

  enum TestPigment: Int {
    case cadmiumYellow, hansaYellow, cadmiumOrange, cadmiumRed
    case quinacridoneMagenta, cobaltViolet, ultramarineBlue, cobaltBlue
    case phthaloBlue, phthaloGreen, permanentGreen, sapGreen, burntSienna
    case titaniumWhite

    var linearRgb: SIMD3<Float> { mixboxPigments[rawValue].linearRgb }
  }

  enum GesturalLoad {
    case thin, medium, loaded

    var rollRange: ClosedRange<Float> {
      switch self {
      case .thin:   return 0.05...0.38
      case .medium: return 0.52...0.72
      case .loaded: return 0.85...0.99
      }
    }
  }

  static func shaderHash11(_ v: Float) -> Float {
    var x = v * 0.1031
    x -= x.rounded(.down)
    x *= x + 33.33
    x *= x + x
    return x - x.rounded(.down)
  }

  static func gesturalSeed(_ load: GesturalLoad, variant: Int = 0) -> Float {
    var remaining = variant
    for i in 0..<400 {
      let seed = Float(i) * 0.25 + 0.125
      if load.rollRange.contains(shaderHash11(seed * 2.39)) {
        if remaining == 0 { return seed }
        remaining -= 1
      }
    }
    return 7.0
  }

  static func testGestural(at pos: SIMD2<Float>, angle: Float,
                           halfLen: Float, halfWidth: Float,
                           pigment: TestPigment, load: GesturalLoad,
                           variant: Int = 0,
                           curvature: Float = 0) -> AbExStroke {
    let c = pigment.linearRgb
    return AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, 0.95, gesturalSeed(load, variant: variant), 0),
      color: SIMD4(c.x, c.y, c.z, 0),
      animation: SIMD4(0, 1, 0, curvature))
  }

  static func testWash(at pos: SIMD2<Float>, angle: Float,
                       halfLen: Float, halfWidth: Float,
                       opacity: Float, pigment: TestPigment,
                       seed: Float) -> AbExStroke {
    let c = pigment.linearRgb
    return AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, seed, 1),
      color: SIMD4(c.x, c.y, c.z, 0),
      animation: SIMD4(0, 1, 0, 0))
  }

  static func testSplatter(at pos: SIMD2<Float>, radius: Float,
                           pigment: TestPigment, heavy: Bool,
                           seed: Float) -> AbExStroke {
    let c = pigment.linearRgb
    let typeRoll: Float = heavy ? 0.85 : 0.50
    return AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, 0, radius),
      sizeOpacity: SIMD4(typeRoll, 0.95, seed, 2),
      color: SIMD4(c.x, c.y, c.z, 0),
      animation: SIMD4(0, 1, 0, 0))
  }

  static func testDrip(at pos: SIMD2<Float>, angle: Float,
                       length: Float, topWidth: Float,
                       srgb: SIMD3<Float>, seed: Float) -> AbExStroke {
    let c = srgbToLinear(srgb)
    return AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, angle, length),
      sizeOpacity: SIMD4(topWidth, 0.97, seed, 3),
      color: SIMD4(c.x, c.y, c.z, 0),
      animation: SIMD4(0, 1, 0, 0))
  }

  static func testKnife(at pos: SIMD2<Float>, angle: Float,
                        halfLen: Float, halfWidth: Float,
                        pigment: TestPigment, seed: Float,
                        curvature: Float = 0) -> AbExStroke {
    let c = pigment.linearRgb
    return AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, 0.95, seed, 4),
      color: SIMD4(c.x, c.y, c.z, 0),
      animation: SIMD4(0, 1, 0, curvature))
  }

  static func testScumble(at pos: SIMD2<Float>, angle: Float,
                          halfLen: Float, halfWidth: Float,
                          opacity: Float, pigment: TestPigment,
                          seed: Float) -> AbExStroke {
    let c = pigment.linearRgb
    return AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, opacity, seed, 5),
      color: SIMD4(c.x, c.y, c.z, 0),
      animation: SIMD4(0, 1, 0, 0))
  }

  static func testLine(at pos: SIMD2<Float>, angle: Float,
                       halfLen: Float, halfWidth: Float,
                       grey: Float, seed: Float,
                       curvature: Float) -> AbExStroke {
    let c = srgbToLinear(SIMD3(grey, grey, grey))
    return AbExStroke(
      posAngle: SIMD4(pos.x, pos.y, angle, halfLen),
      sizeOpacity: SIMD4(halfWidth, 0.9, seed, 6),
      color: SIMD4(c.x, c.y, c.z, 0),
      animation: SIMD4(0, 1, 0, curvature))
  }

  private static let bandA: Float = -0.27
  private static let bandB: Float = -0.14
  private static let bandC: Float = 0.03
  private static let bandD: Float = 0.22
  private static let bandE: Float = 0.38

  static let mixingScript: [PaintTestEvent] = [
    PaintTestEvent(time: 0.3, label: "E  Three Ultramarine bases laid (wetness test)", strokes: [
      testGestural(at: SIMD2(-0.12, bandE), angle: 0, halfLen: 0.05, halfWidth: 0.014,
                   pigment: .ultramarineBlue, load: .medium, variant: 0),
      testGestural(at: SIMD2( 0.00, bandE), angle: 0, halfLen: 0.05, halfWidth: 0.014,
                   pigment: .ultramarineBlue, load: .medium, variant: 1),
      testGestural(at: SIMD2( 0.12, bandE), angle: 0, halfLen: 0.05, halfWidth: 0.014,
                   pigment: .ultramarineBlue, load: .medium, variant: 2),
    ]),

    PaintTestEvent(time: 0.5, label: "A  Cadmium Yellow wash", strokes: [
      testWash(at: SIMD2(-0.15, bandA), angle: 0, halfLen: 0.085, halfWidth: 0.055,
               opacity: 0.55, pigment: .cadmiumYellow, seed: 11),
    ]),
    PaintTestEvent(time: 0.8, label: "E  Yellow into WET blue (0.5 s) → should mix green and smear", strokes: [
      testGestural(at: SIMD2(-0.12, bandE), angle: 1.3, halfLen: 0.05, halfWidth: 0.014,
                   pigment: .cadmiumYellow, load: .medium, variant: 3),
    ]),
    PaintTestEvent(time: 1.1, label: "A  Ultramarine wash over yellow → overlap should be GREEN, not grey", strokes: [
      testWash(at: SIMD2(-0.07, bandA), angle: 0, halfLen: 0.085, halfWidth: 0.055,
               opacity: 0.55, pigment: .ultramarineBlue, seed: 23),
    ]),
    PaintTestEvent(time: 1.5, label: "D  Thick blobs laid early: skin forms while the inside stays wet", strokes: [
      testSplatter(at: SIMD2(0.05, bandD - 0.06), radius: 0.021,
                   pigment: .ultramarineBlue, heavy: true, seed: 141),
      testSplatter(at: SIMD2(0.11, bandD - 0.07), radius: 0.021,
                   pigment: .cadmiumYellow, heavy: true, seed: 143),
    ]),
    PaintTestEvent(time: 1.6, label: "A  Cadmium Red wash", strokes: [
      testWash(at: SIMD2(0.07, bandA), angle: 0, halfLen: 0.085, halfWidth: 0.055,
               opacity: 0.55, pigment: .cadmiumRed, seed: 37),
    ]),
    PaintTestEvent(time: 2.1, label: "A  Phthalo Green wash over red → overlap goes deep brown / near black", strokes: [
      testWash(at: SIMD2(0.15, bandA), angle: 0, halfLen: 0.085, halfWidth: 0.055,
               opacity: 0.55, pigment: .phthaloGreen, seed: 41),
    ]),

    PaintTestEvent(time: 2.7, label: "B  Cadmium Yellow gestural base", strokes: [
      testGestural(at: SIMD2(-0.11, bandB), angle: 0, halfLen: 0.075, halfWidth: 0.016,
                   pigment: .cadmiumYellow, load: .medium, variant: 4),
    ]),
    PaintTestEvent(time: 3.2, label: "B  Cadmium Red across wet yellow → junction should be ORANGE", strokes: [
      testGestural(at: SIMD2(-0.11, bandB), angle: 1.1, halfLen: 0.075, halfWidth: 0.016,
                   pigment: .cadmiumRed, load: .medium, variant: 5),
    ]),
    PaintTestEvent(time: 3.7, label: "B  Cobalt Blue gestural base", strokes: [
      testGestural(at: SIMD2(0.11, bandB), angle: 0, halfLen: 0.075, halfWidth: 0.016,
                   pigment: .cobaltBlue, load: .medium, variant: 6),
    ]),
    PaintTestEvent(time: 4.2, label: "B  Cadmium Orange across wet blue → junction goes muted grey-brown", strokes: [
      testGestural(at: SIMD2(0.11, bandB), angle: 1.1, halfLen: 0.075, halfWidth: 0.016,
                   pigment: .cadmiumOrange, load: .medium, variant: 7),
    ]),

    PaintTestEvent(time: 4.5, label: "B  Titanium White knife into wet blue/orange → light tints, not grey", strokes: [
      testKnife(at: SIMD2(0.11, bandB), angle: -0.45, halfLen: 0.08, halfWidth: 0.014,
                pigment: .titaniumWhite, seed: 139),
    ]),

    PaintTestEvent(time: 4.8, label: "C  Sap Green wash as the ground", strokes: [
      testWash(at: SIMD2(0, bandC), angle: 0.4, halfLen: 0.13, halfWidth: 0.09,
               opacity: 0.45, pigment: .sapGreen, seed: 53),
    ]),
    PaintTestEvent(time: 5.3, label: "E  Yellow onto PARTLY DRY blue (5 s) → less mixing, more sits on top", strokes: [
      testGestural(at: SIMD2(0.0, bandE), angle: 1.3, halfLen: 0.05, halfWidth: 0.014,
                   pigment: .cadmiumYellow, load: .medium, variant: 8),
    ]),
    PaintTestEvent(time: 5.7, label: "C  Cadmium Red gestural over the wash", strokes: [
      testGestural(at: SIMD2(0, bandC), angle: 0.3, halfLen: 0.11, halfWidth: 0.017,
                   pigment: .cadmiumRed, load: .medium, variant: 9, curvature: 0.3),
    ]),
    PaintTestEvent(time: 6.4, label: "C  Dry scumble drags Hansa Yellow over the ridges", strokes: [
      testScumble(at: SIMD2(0, bandC - 0.02), angle: -0.5, halfLen: 0.12, halfWidth: 0.045,
                  opacity: 0.7, pigment: .hansaYellow, seed: 61),
    ]),
    PaintTestEvent(time: 7.1, label: "C  Ultramarine splatters land on top", strokes: [
      testSplatter(at: SIMD2(-0.05, bandC + 0.03), radius: 0.016,
                   pigment: .ultramarineBlue, heavy: false, seed: 71),
      testSplatter(at: SIMD2( 0.02, bandC - 0.04), radius: 0.012,
                   pigment: .ultramarineBlue, heavy: false, seed: 73),
      testSplatter(at: SIMD2( 0.06, bandC + 0.02), radius: 0.020,
                   pigment: .ultramarineBlue, heavy: false, seed: 79),
    ]),
    PaintTestEvent(time: 7.7, label: "C  Poured trail crosses the stack", strokes: [
      testDrip(at: SIMD2(-0.02, bandC), angle: 0.9, length: 0.28, topWidth: 0.004,
               srgb: SIMD3(0.02, 0.02, 0.02), seed: 83),
    ]),
    PaintTestEvent(time: 8.3, label: "C  Charcoal line over everything", strokes: [
      testLine(at: SIMD2(0, bandC), angle: -0.9, halfLen: 0.15, halfWidth: 0.0011,
               grey: 0.08, seed: 89, curvature: 1.2),
    ]),
    PaintTestEvent(time: 9.0, label: "C  Knife drags orange through the stack → streaks of colours below", strokes: [
      testKnife(at: SIMD2(0, bandC), angle: 0.15, halfLen: 0.12, halfWidth: 0.016,
                pigment: .cadmiumOrange, seed: 97, curvature: 0.2),
    ]),

    PaintTestEvent(time: 9.7, label: "D  Knife pass 1: Burnt Sienna", strokes: [
      testKnife(at: SIMD2(-0.09, bandD), angle: 0.0, halfLen: 0.07, halfWidth: 0.020,
                pigment: .burntSienna, seed: 101),
    ]),
    PaintTestEvent(time: 10.2, label: "D  Knife pass 2: Cadmium Yellow builds height", strokes: [
      testKnife(at: SIMD2(-0.09, bandD), angle: 0.35, halfLen: 0.07, halfWidth: 0.020,
                pigment: .cadmiumYellow, seed: 103),
    ]),
    PaintTestEvent(time: 10.7, label: "D  Knife pass 3: Cobalt Violet → ridges should catch the light", strokes: [
      testKnife(at: SIMD2(-0.09, bandD), angle: -0.35, halfLen: 0.07, halfWidth: 0.020,
                pigment: .cobaltViolet, seed: 107),
    ]),
    PaintTestEvent(time: 11.5, label: "D  Loaded brush dragged across the impasto → grooves, smearing", strokes: [
      testGestural(at: SIMD2(-0.09, bandD), angle: 1.5, halfLen: 0.10, halfWidth: 0.015,
                   pigment: .cadmiumRed, load: .loaded, variant: 0),
    ]),
    PaintTestEvent(time: 12.1, label: "D  Fresh thick blobs (lower row), fully wet", strokes: [
      testSplatter(at: SIMD2(0.05, bandD + 0.05), radius: 0.021,
                   pigment: .ultramarineBlue, heavy: true, seed: 109),
      testSplatter(at: SIMD2(0.11, bandD + 0.06), radius: 0.021,
                   pigment: .cadmiumRed, heavy: true, seed: 127),
    ]),
    PaintTestEvent(time: 12.9, label: "D  Knife through both rows: skinned blobs tear, fresh ones flatten", strokes: [
      testKnife(at: SIMD2(0.08, bandD), angle: 1.45, halfLen: 0.085, halfWidth: 0.024,
                pigment: .sapGreen, seed: 131),
    ]),

    PaintTestEvent(time: 13.6, label: "E  Yellow onto DRIEST blue (13 s) → mostly layered, least mixing", strokes: [
      testGestural(at: SIMD2(0.12, bandE), angle: 1.3, halfLen: 0.05, halfWidth: 0.014,
                   pigment: .cadmiumYellow, load: .medium, variant: 10),
    ]),

    PaintTestEvent(time: 14.5, label: "Done. Compare bands A–E; canvas clears and restarts at 20 s", strokes: []),
  ]

  func generatePaintTestStrokes() -> [AbExStroke] {
    decayFlow()
    decayDensity()
    advanceAnimatingStrokes()

    paintTestDryMultiplier = Self.paintTestDryMultiplier
    paintTestClock += dt

    var instant = [AbExStroke]()
    var animated = [AbExStroke]()
    let script = Self.paintTestScript
    while paintTestEventIndex < script.count,
          script[paintTestEventIndex].time <= paintTestClock {
      let event = script[paintTestEventIndex]
      paintTestEventIndex += 1
      paintTestStatus = String(format: "%4.1fs  %@", event.time, event.label)
      for s in event.strokes {
        switch Int(s.sizeOpacity.w) {
        case 0, 1, 4, 5: animated.append(s)
        default:         instant.append(s)
        }
      }
    }
    enqueueAnimatingStrokes(animated)

    if paintTestClock >= Self.paintTestLoopDuration {
      restartPaintTest()
    }
    return emitAnimatedStrokes(into: instant)
  }

  func restartPaintTest() {
    paintTestClock = 0
    paintTestEventIndex = 0
    paintTestStatus = "Clearing canvas…"
    animatingStrokes.removeAll()
    for i in flowField.indices { flowField[i] = .zero }
    for i in densityGrid.indices { densityGrid[i] = 0 }
    for i in paintedGrid.indices { paintedGrid[i] = 0 }
    pendingClearFrames = Int(Self.maxFramesInFlight) + 1
  }
}

#endif
