//
//  ThreeDBarsVisualizerViewModel.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import Foundation
import QuartzCore
import RealityKit

extension ThreeDBarsVisualizerView {
  @MainActor
  final class ThreeDBarsVisualizerViewModel {
    var targetValues: [32 of Float] = .init(repeating: 0.0)
    var barEntities: [Entity] = []

    private var smoothedValues: [32 of Float] = .init(repeating: 0.0)
    private var lastFrameTime: CFTimeInterval = 0
    private var displayLinkStream: DisplayLinkStream?
    private var smoothingTask: Task<Void, Never>?

    private let attackTime: Float = 0.04
    private let releaseTime: Float = 0.12

    func startSmoothing() {
      guard smoothingTask == nil else { return }
      lastFrameTime = CACurrentMediaTime()
      let stream = DisplayLinkStream()
      displayLinkStream = stream
      smoothingTask = Task { [weak self] in
        defer { self?.smoothingTask = nil }
        for await _ in stream.frames {
          guard !Task.isCancelled else { break }
          self?.updateSmoothedValues()
        }
      }
    }

    func stopSmoothing() {
      smoothingTask?.cancel()
      smoothingTask = nil
      displayLinkStream?.stop()
      displayLinkStream = nil
    }

    private func updateSmoothedValues() {
      let now = CACurrentMediaTime()
      let dt = Float(now - lastFrameTime)
      lastFrameTime = now

      let entities = barEntities
      for index in 0..<min(targetValues.count, smoothedValues.count) {
        let targetHeight = max(0.01, targetValues[index] * 10)

        let timeConstant = targetHeight > smoothedValues[index] ? attackTime : releaseTime
        let factor = 1.0 - exp(-dt / timeConstant)

        smoothedValues[index] += (targetHeight - smoothedValues[index]) * factor

        if index < entities.count {
          entities[index].scale = [1.0, smoothedValues[index], 1.0]
        }
      }
    }
  }
}
