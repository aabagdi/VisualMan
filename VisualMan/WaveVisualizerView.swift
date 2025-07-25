//
//  WaveVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/24/25.
//

import SwiftUI

struct WaveVisualizerView: View {
  @State private var time: Float = 0
  @State private var smoothedBass: Float = 0
  @State private var smoothedMid: Float = 0
  @State private var smoothedHigh: Float = 0
  @State private var peakLevel: Float = 0
  
  let audioLevels: [Float]
  
  private var bassLevel: Float {
    guard audioLevels.count >= 8 else { return 0 }
    return audioLevels[0..<8].reduce(0, +) / 8.0
  }
  
  private var midLevel: Float {
    guard audioLevels.count >= 32 else { return 0 }
    return audioLevels[8..<24].reduce(0, +) / 16.0
  }
  
  private var highLevel: Float {
    guard audioLevels.count >= 32 else { return 0 }
    return audioLevels[24..<32].reduce(0, +) / 8.0
  }
  
  var body: some View {
    TimelineView(.animation) { timeline in
      Rectangle()
        .fill(.white)
        .colorEffect(
          ShaderLibrary.wave(
            .float(time),
            .float(smoothedBass),
            .float(smoothedMid),
            .float(smoothedHigh),
            .float(peakLevel)
          )
        )
        .onChange(of: timeline.date) {
          smoothedBass = smoothedBass * 0.7 + bassLevel * 0.3
          smoothedMid = smoothedMid * 0.8 + midLevel * 0.2
          smoothedHigh = smoothedHigh * 0.6 + highLevel * 0.4

          let currentPeak = max(bassLevel, midLevel, highLevel)
          if currentPeak > peakLevel {
            peakLevel = currentPeak
          } else {
            peakLevel *= 0.95
          }
          
          time += 0.016 * (1.0 + smoothedBass * 2.0)
        }
        .ignoresSafeArea()
    }
  }
}
