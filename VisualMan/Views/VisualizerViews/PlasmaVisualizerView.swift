//
//  PlasmaVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

import SwiftUI

struct PlasmaVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    ShaderVisualizerView(audioLevels: audioLevels) { audio in
      Rectangle()
        .plasmaShader(time: audio.time,
                      smoothedBass: audio.bass,
                      smoothedMid: audio.mid,
                      smoothedHigh: audio.high)
    }
  }
}
