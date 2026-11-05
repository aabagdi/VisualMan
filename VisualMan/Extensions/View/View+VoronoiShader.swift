//
//  View+VoronoiShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

extension View {
  func voronoiShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.voronoi, audio: audio)
  }
}
