//
//  FireworksVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct FireworksVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    ShaderVisualizerView(audioLevels: audioLevels) { audio in
      let peakLevel = min((audio.bass + audio.mid + audio.high) / 3.0 * 1.2, 1.0)
      Rectangle()
        .fireworksShader(time: audio.time,
                         smoothedBass: audio.bass,
                         smoothedMid: audio.mid,
                         smoothedHigh: audio.high,
                         peakLevel: peakLevel)
    }
  }
}
