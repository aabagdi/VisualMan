//
//  FireworksVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct FireworksVisualizerView: View {
  @State private var audio = SmoothedAudio()
  
  let audioLevels: [1024 of Float]
  
  private var peakLevel: Float {
    let overall = (audioLevels.bassLevel + audioLevels.midLevel + audioLevels.highLevel) / 3.0
    return min(overall * 1.2, 1.0)
  }
  
  var body: some View {
    TimelineView(.animation) { timeline in
      Rectangle()
        .fireworksShader(time: audio.time,
                         smoothedBass: audio.bass,
                         smoothedMid: audio.mid,
                         smoothedHigh: audio.high,
                         peakLevel: peakLevel)
        .onChange(of: timeline.date) { oldValue, newValue in
          let dt = min(Float(newValue.timeIntervalSince(oldValue)), 1.0 / 30.0)
          withAnimation(.smooth) {
            audio.update(from: audioLevels, dt: dt)
          }
        }
        .ignoresSafeArea()
    }
    // .debugOverlay(smoothedBass: audio.bass, smoothedMid: audio.mid, smoothedHigh: audio.high)
  }
}
