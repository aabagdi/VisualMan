//
//  InkVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct InkVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    ShaderVisualizerView(audioLevels: audioLevels) { audio in
      Rectangle()
        .inkShader(time: audio.time,
                   smoothedBass: audio.bass,
                   smoothedMid: audio.mid,
                   smoothedHigh: audio.high)
    }
  }
}
