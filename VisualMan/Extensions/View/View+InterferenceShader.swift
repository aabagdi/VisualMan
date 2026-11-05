//
//  View+InterferenceShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func interferenceShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.interference, audio: audio)
  }
}
