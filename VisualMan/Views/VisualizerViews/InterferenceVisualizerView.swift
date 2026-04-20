//
//  InterferenceVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct InterferenceVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    ShaderVisualizerView(audioLevels: audioLevels) { audio in
      Rectangle()
        .interferenceShader(time: audio.time,
                            smoothedBass: audio.bass,
                            smoothedMid: audio.mid,
                            smoothedHigh: audio.high)
    }
  }
}
