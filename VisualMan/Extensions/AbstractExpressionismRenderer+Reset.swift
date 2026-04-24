//
//  AbstractExpressionismRenderer+Reset.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

import Foundation

extension AbstractExpressionismRenderer {
  func reset() {
    time = 0
    wallClock = 0
    lastFrameTime = 0
    dt = 1.0 / 60.0

    envelope = .zero
    slowEnvelope = .zero
    smoothedBass = 0

    lastGesturalTime = -10
    lastWashTime = -10
    lastSplatterTime = -10

    hueOffset = 0
    strokeSeed = 0
    songSeed = Float.random(in: 0..<1000)
    warmBias = Float.random(in: 0.2..<0.8)

    resumeSuppressionRemaining = 0
    resumeFadeIn = 1.0

    isFirstFrame = true
    currentIsA = true

    cameraPhase = 0
  }
}
