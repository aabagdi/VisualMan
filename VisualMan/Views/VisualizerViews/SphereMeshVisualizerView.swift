//
//  SphereMeshVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct SphereMeshVisualizerView: View {
  @State private var audio = SmoothedAudio()
  
  let audioLevels: [1024 of Float]
  
  var body: some View {
    TimelineView(.animation) { timeline in
      Rectangle()
        .sphereMeshShader(time: audio.time,
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
