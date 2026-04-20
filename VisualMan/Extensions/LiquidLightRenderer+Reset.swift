//
//  LiquidLightRenderer+Reset.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/10/26.
//

import Metal

extension LiquidLightRenderer {
  func reset() {
    time = 0
    wallClock = 0
    lastFrameTime = 0
    smoothedBass = 0
    smoothedSpeed = 0.25
    lastDropWallTime = -10
    drops = Array(repeating: SIMD4<Float>(0, 0, -1, 0), count: 4)
    nextDropSlot = 0
    dropHueCounter = 0
    envelope = .zero
    slowEnvelope = .zero
    resumeSuppressionRemaining = 0
    resumeFadeIn = 1.0
  }
}
