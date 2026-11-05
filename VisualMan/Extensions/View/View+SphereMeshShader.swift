//
//  View+SphereMeshShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

extension View {
  func sphereMeshShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.sphereMesh, audio: audio)
  }
}
