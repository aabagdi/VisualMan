//
//  AbstractExpressionismRenderer+PaintTestSmear.swift
//  VisualMan
//
//  Created on 11/4/26.
//

#if DEBUG && !targetEnvironment(simulator)
import Foundation
import simd

extension AbstractExpressionismRenderer {
  private static let smearRow1: Float = -0.27
  private static let smearRow2: Float = -0.08
  private static let smearRow3: Float = 0.12
  private static let smearRow4: Float = 0.32
  
  static let smearScript: [PaintTestEvent] = [
    PaintTestEvent(time: 0.5,
                   label: "Four heavy blobs. Each row tests one kind of contact",
                   strokes: [
                    testSplatter(at: SIMD2(-0.04, smearRow1), radius: 0.040,
                                 pigment: .cadmiumYellow, heavy: true, seed: 301),
                    testSplatter(at: SIMD2(-0.04, smearRow2), radius: 0.040,
                                 pigment: .ultramarineBlue, heavy: true, seed: 303),
                    testSplatter(at: SIMD2(-0.04, smearRow3), radius: 0.040,
                                 pigment: .cadmiumRed, heavy: true, seed: 305),
                    testSplatter(at: SIMD2(-0.04, smearRow4), radius: 0.040,
                                 pigment: .phthaloGreen, heavy: true, seed: 307),
                   ]),
    PaintTestEvent(time: 1.0,
                   label: "Row 4: a brush runs along the blob's lower edge. Blob should crack regardless",
                   strokes: [
                    testGestural(at: SIMD2(0.02, smearRow4 + 0.045), angle: 0.0, halfLen: 0.14, halfWidth: 0.010,
                                 pigment: .cobaltViolet, load: .medium, variant: 2),
                   ]),
    PaintTestEvent(time: 1.5,
                   label: "Row 1: knife through the RIGHT half while wet. Left half should still crack",
                   strokes: [
                    testKnife(at: SIMD2(0.03, smearRow1), angle: 0.0, halfLen: 0.09, halfWidth: 0.020,
                              pigment: .titaniumWhite, seed: 311),
                   ]),
    PaintTestEvent(time: 2.0,
                   label: "Row 2: brush across the wet blob. The crossed band flattens, the rest cracks",
                   strokes: [
                    testGestural(at: SIMD2(0.0, smearRow2 + 0.01), angle: 0.15, halfLen: 0.12, halfWidth: 0.012,
                                 pigment: .cadmiumOrange, load: .loaded, variant: 1),
                   ]),
    PaintTestEvent(time: 8.0,
                   label: "Skins forming. Rows 1 and 2: flattened parts stay smooth",
                   strokes: []),
    PaintTestEvent(time: 14.0,
                   label: "Craquelure due on every blob's untouched paint (rows 1, 2, 4 included)",
                   strokes: []),
    PaintTestEvent(time: 18.0,
                   label: "Row 3: THIN brush over the cured blob (texture shows through) + knife passing beside it",
                   strokes: [
                    testGestural(at: SIMD2(0.0, smearRow3), angle: -0.2, halfLen: 0.12, halfWidth: 0.011,
                                 pigment: .titaniumWhite, load: .thin, variant: 3),
                    testKnife(at: SIMD2(0.10, smearRow3 - 0.07), angle: 0.0, halfLen: 0.08, halfWidth: 0.018,
                              pigment: .burntSienna, seed: 331),
                   ]),
    PaintTestEvent(time: 26.0,
                   label: "Row 3 check: blob dome and cracks intact beside the knife; thin white shows them",
                   strokes: []),
    PaintTestEvent(time: 36.0,
                   label: "Done. Canvas clears and restarts at 45 s",
                   strokes: []),
  ]
}

#endif
