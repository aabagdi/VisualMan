//
//  View+MetaballShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

import SwiftUI

extension View {
  func metaballShader(audio: SmoothedAudio) -> some View {
    audioColorEffect(ShaderLibrary.metaball, audio: audio)
  }
}
