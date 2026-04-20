//
//  VoronoiVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

struct VoronoiVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    ShaderVisualizerView(audioLevels: audioLevels) { audio in
      Rectangle()
        .voronoiShader(time: audio.time,
                       smoothedBass: audio.bass,
                       smoothedMid: audio.mid,
                       smoothedHigh: audio.high)
    }
  }
}
