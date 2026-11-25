//
//  VoronoiVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

struct VoronoiVisualizerView: View {
  var body: some View {
    ShaderVisualizerView { audio in
      Rectangle()
        .voronoiShader(audio: audio)
    }
  }
}
