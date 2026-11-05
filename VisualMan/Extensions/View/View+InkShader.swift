//
//  View+InkShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

extension View {
  func inkShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.ink, audio: audio)
  }
}
