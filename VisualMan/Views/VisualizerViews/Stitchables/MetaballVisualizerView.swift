//
//  MetaballVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

import SwiftUI

struct MetaballVisualizerView: View {
  var body: some View {
    ShaderVisualizerView { audio in
      Rectangle()
        .metaballShader(audio: audio)
    }
  }
}
