//
//  ThreeDBarsVisualizerViewModel.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import Foundation

extension ThreeDBarsVisualizerView {
  @Observable
  @MainActor
  final class ThreeDBarsVisualizerViewModel {
    var smoothedValues: [32 of Float] = .init(repeating: 0.0)
    var targetValues: [32 of Float] = .init(repeating: 0.0)
    
    private var displayLinkStream: DisplayLinkStream?
    private var smoothingTask: Task<Void, Never>?
    
    func startSmoothing() {
      guard smoothingTask == nil else { return }
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
      for index in 0..<min(targetValues.count, smoothedValues.count) {
        let targetHeight = max(0.01, targetValues[index] * 10)
        
        let attack: Float = 0.45
        let release: Float = 0.2
        
        if targetHeight > smoothedValues[index] {
          smoothedValues[index] += (targetHeight - smoothedValues[index]) * attack
        } else {
          smoothedValues[index] += (targetHeight - smoothedValues[index]) * release
        }
      }
    }
  }
}
