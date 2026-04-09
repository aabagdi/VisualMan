//
//  VoronoiVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

struct VoronoiVisualizerView: View {
  @State private var audio = SmoothedAudio()
  
  let audioLevels: [1024 of Float]
  
  var body: some View {
    TimelineView(.animation) { timeline in
      Rectangle()
        .voronoiShader(time: audio.time,
                       smoothedBass: audio.bass,
                       smoothedMid: audio.mid,
                       smoothedHigh: audio.high)
        .onChange(of: timeline.date) { oldValue, newValue in
          let dt = min(Float(newValue.timeIntervalSince(oldValue)), 1.0 / 30.0)
          withAnimation(.smooth) {
            audio.update(from: audioLevels, dt: dt)
          }
        }
        .ignoresSafeArea()
    }
  }
}
