//
//  AbstractExpressionismRenderer+Reset.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

#if !targetEnvironment(simulator)
import Foundation

extension AbstractExpressionismRenderer {
  func beginSong(key: String) {
    var h: UInt32 = 2166136261
    for byte in key.utf8 {
      h ^= UInt32(byte)
      h = h &* 16777619
    }
    songSeed = Float(h % 100_000) / 100.0
    pigmentWeightsSeed = -1
  }

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
    lastKnifeTime = -10
    lastPollockTime = -10
    lastScumbleTime = -10
    pollockEventCounter = 0

    hueOffset = 0
    strokeSeed = 0
    songSeed = Float.random(in: 0..<1000)
    warmBias = Float.random(in: 0.2..<0.8)

    resumeSuppressionRemaining = 0
    resumeFadeIn = 1.0

    isFirstFrame = true
    currentIsA = true

    cameraPhase = 0

    currentGestureRemaining = 0
    currentGestureAngle = 0
    currentGestureCenter = .zero
    currentGestureStarted = 0
    currentGestureSpan = 0.30

    for i in 0..<flowField.count { flowField[i] = .zero }
    for i in 0..<densityGrid.count { densityGrid[i] = 0 }
    for i in 0..<paintedGrid.count { paintedGrid[i] = 0 }

    animatingStrokes.removeAll()

    paintTestClock = 0
    paintTestEventIndex = 0

    pendingClearFrames = Int(Self.maxFramesInFlight) + 1
  }
}

#endif
