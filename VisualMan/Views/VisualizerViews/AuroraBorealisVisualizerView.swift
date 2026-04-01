//
//  AuroraBorealisVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct AuroraBorealisVisualizerView: View {
  @State private var time: Float = 0
  @State private var smoothedBass: Float = 0
  @State private var smoothedMid: Float = 0
  @State private var smoothedHigh: Float = 0
  
  let audioLevels: [1024 of Float]
  
  var body: some View {
    TimelineView(.animation) { timeline in
      Rectangle()
        .auroraBorealisShader(time: time,
                              smoothedBass: smoothedBass,
                              smoothedMid: smoothedMid,
                              smoothedHigh: smoothedHigh)
        .onChange(of: timeline.date) {
          withAnimation(.smooth) {
            smoothedBass = smoothedBass * 0.5 + audioLevels.bassLevel * 0.5
            smoothedMid = smoothedMid * 0.6 + audioLevels.midLevel * 0.4
            smoothedHigh = smoothedHigh * 0.4 + audioLevels.highLevel * 0.6
            time += 0.016 * (1.0 + smoothedBass * 0.5)
          }
        }
        .ignoresSafeArea()
    }
  }
}
