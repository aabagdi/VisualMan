//
//  View+JuliaShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func juliaShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.julia, audio: audio)
  }
}
