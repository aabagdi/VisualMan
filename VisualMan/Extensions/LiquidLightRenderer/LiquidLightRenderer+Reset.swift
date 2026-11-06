//
//  LiquidLightRenderer+Reset.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

#if !targetEnvironment(simulator)
import Metal

extension LiquidLightRenderer {
  func reset() {
    time = 0
    wallClock = 0
    lastFrameTime = 0
    historyValid = false
    simValid = false
    tiltPhase = 0
    tiltAxis = 0.6
    lastPressBass = 0
    smoothedBass = 0
    smoothedSpeed = 0.25
    lastDropWallTime = -10
    nextDripWallTime = 1.5
    drops = Array(repeating: SIMD4<Float>(0, 0, -1, 0), count: 4)
    dropSizes = Array(repeating: 0.05, count: 4)
    nextDropSlot = 0
    envelope = .zero
    slowEnvelope = .zero
    resumeSuppressionRemaining = 0
    resumeFadeIn = 1.0
  }
}

#endif
