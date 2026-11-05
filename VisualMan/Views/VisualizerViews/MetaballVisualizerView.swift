//
//  MetaballVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

import SwiftUI

struct MetaballVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    ShaderVisualizerView(audioLevels: audioLevels) { audio in
      Rectangle()
        .metaballShader(audio: audio)
    }
  }
}
