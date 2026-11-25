//
//  AuroraBorealisVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct AuroraBorealisVisualizerView: View {
  var body: some View {
    ShaderVisualizerView { audio in
      Rectangle()
        .auroraBorealisShader(audio: audio)
    }
  }
}
