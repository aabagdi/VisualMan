//
//  ThreeDBarsVisualizerViewModel.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import Foundation
import Combine

extension ThreeDBarsVisualizerView {
  @Observable
  @MainActor
  final class ThreeDBarsVisualizerViewModel {
    var smoothedValues = [32 of Float](repeating: 0.0)
    private var timer: Timer?
    
    func startSmoothing(targetValues: [32 of Float]) {
      if smoothedValues.isEmpty {
        smoothedValues = [32 of Float](repeating: 0.01)
      }
      
      timer?.invalidate()
      timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
        Task { @MainActor in
          self?.updateSmoothedValues(targetValues: targetValues)
        }
      }
    }
    
    func stopSmoothing() {
      timer?.invalidate()
      timer = nil
    }
    
    private func updateSmoothedValues(targetValues: [32 of Float]) {
      for index in 0..<min(targetValues.count, smoothedValues.count) {
        let targetHeight = max(0.01, targetValues[index] * 10)
        
        let attack: Float = 0.7
        let release: Float = 0.15
        
        if targetHeight > smoothedValues[index] {
          smoothedValues[index] += (targetHeight - smoothedValues[index]) * attack
        } else {
          smoothedValues[index] += (targetHeight - smoothedValues[index]) * release
        }
      }
    }
  }
}
