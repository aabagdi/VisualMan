//
//  JuliaVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct JuliaVisualizerView: View {
  var body: some View {
    ShaderVisualizerView { audio in
      Rectangle()
        .juliaShader(audio: audio)
    }
  }
}
