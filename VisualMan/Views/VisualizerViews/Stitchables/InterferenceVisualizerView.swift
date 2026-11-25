//
//  InterferenceVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct InterferenceVisualizerView: View {
  var body: some View {
    ShaderVisualizerView { audio in
      Rectangle()
        .interferenceShader(audio: audio)
    }
  }
}
