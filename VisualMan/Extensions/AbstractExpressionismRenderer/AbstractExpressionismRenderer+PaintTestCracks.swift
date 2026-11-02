//
//  AbstractExpressionismRenderer+PaintTestCracks.swift
//  VisualMan
//
//  Created on 11/2/26.
//

#if !targetEnvironment(simulator)
import Foundation
import simd

extension AbstractExpressionismRenderer {
  private static let crackRow1: Float = -0.26
  private static let crackRow2: Float = -0.06
  private static let crackRow3: Float = 0.15
  private static let crackRow4: Float = 0.34

  static let crackScript: [PaintTestEvent] = [
    PaintTestEvent(time: 0.5, label: "Heavy blobs (top row): should skin over, then craze with hairlines", strokes: [
      testSplatter(at: SIMD2(-0.12, crackRow1), radius: 0.032,
                   pigment: .ultramarineBlue, heavy: true, seed: 201),
      testSplatter(at: SIMD2( 0.00, crackRow1), radius: 0.032,
                   pigment: .cadmiumRed, heavy: true, seed: 203),
      testSplatter(at: SIMD2( 0.12, crackRow1), radius: 0.032,
                   pigment: .cadmiumYellow, heavy: true, seed: 205),
    ]),
    PaintTestEvent(time: 0.9, label: "Medium blobs (second row): thinner, should NOT craze", strokes: [
      testSplatter(at: SIMD2(-0.12, crackRow2), radius: 0.032,
                   pigment: .ultramarineBlue, heavy: false, seed: 211),
      testSplatter(at: SIMD2( 0.00, crackRow2), radius: 0.032,
                   pigment: .cadmiumRed, heavy: false, seed: 213),
      testSplatter(at: SIMD2( 0.12, crackRow2), radius: 0.032,
                   pigment: .cadmiumYellow, heavy: false, seed: 215),
    ]),
    PaintTestEvent(time: 1.3, label: "Third row: stacked knife slab (left) vs one big blob (right)", strokes: [
      testKnife(at: SIMD2(-0.09, crackRow3), angle: 0.0, halfLen: 0.08, halfWidth: 0.030,
                pigment: .burntSienna, seed: 221),
      testSplatter(at: SIMD2(0.10, crackRow3), radius: 0.048,
                   pigment: .phthaloGreen, heavy: true, seed: 223),
    ]),
    PaintTestEvent(time: 1.8, label: "Second slab pass builds the knife stack higher", strokes: [
      testKnife(at: SIMD2(-0.09, crackRow3), angle: 0.25, halfLen: 0.08, halfWidth: 0.030,
                pigment: .burntSienna, seed: 227),
    ]),
    PaintTestEvent(time: 2.2, label: "Bottom row: one heavy blob that a knife will cut once it has cured", strokes: [
      testSplatter(at: SIMD2(0.0, crackRow4), radius: 0.036,
                   pigment: .quinacridoneMagenta, heavy: true, seed: 231),
    ]),
    PaintTestEvent(time: 6.0, label: "Drying x3: skins forming (gloss dulls, surface puckers)", strokes: []),
    PaintTestEvent(time: 12.0, label: "Craquelure should now be visible on the heavy blobs and the slab", strokes: []),
    PaintTestEvent(time: 20.0, label: "Hairlines strengthen as the skin fully cures", strokes: []),
    PaintTestEvent(time: 28.0, label: "Knife through the cured magenta blob: skin tears and wrinkles", strokes: [
      testKnife(at: SIMD2(0.0, crackRow4), angle: 0.3, halfLen: 0.09, halfWidth: 0.022,
                pigment: .titaniumWhite, seed: 241),
    ]),
    PaintTestEvent(time: 36.0, label: "Done. Compare rows; canvas clears and restarts at 45 s", strokes: []),
  ]
}

#endif
