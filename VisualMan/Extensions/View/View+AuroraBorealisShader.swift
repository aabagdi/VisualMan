//
//  View+AuroraBorealisShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

extension View {
  func auroraBorealisShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.auroraBorealis, audio: audio)
  }
}
