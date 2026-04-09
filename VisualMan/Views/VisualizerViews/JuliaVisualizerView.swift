//
//  JuliaVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct JuliaVisualizerView: View {
  @State private var time: Float = 0
  @State private var smoothedBass: Float = 0
  @State private var smoothedMid: Float = 0
  @State private var smoothedHigh: Float = 0
  
  let audioLevels: [1024 of Float]
  
  var body: some View {
    TimelineView(.animation) { timeline in
      Rectangle()
        .juliaShader(time: time,
                     smoothedBass: smoothedBass,
                     smoothedMid: smoothedMid,
                     smoothedHigh: smoothedHigh)
        .onChange(of: timeline.date) {
          withAnimation(.easeInOut) {
            smoothedBass = smoothedBass * 0.5 + audioLevels.bassLevel * 0.5
            smoothedMid = smoothedMid * 0.6 + audioLevels.midLevel * 0.4
            smoothedHigh = smoothedHigh * 0.4 + audioLevels.highLevel * 0.6
            time += 0.016 * (1.0 + smoothedBass * 0.5)
          }
        }
        .ignoresSafeArea()
    }
    // .debugOverlay(smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh)
  }
}
