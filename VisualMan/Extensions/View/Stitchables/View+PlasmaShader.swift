//
//  View+PlasmaShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

import SwiftUI

extension View {
  func plasmaShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.plasma, audio: audio)
  }
}
