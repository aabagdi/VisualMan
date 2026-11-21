//
//  View+AudioColorEffect.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import SwiftUI

struct AudioColorEffectShader: ViewModifier {
  let shaderFunction: ShaderFunction
  var audio: SmoothedAudio

  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          Shader(function: shaderFunction, arguments: [
            .float(audio.time),
            .float(audio.bass),
            .float(audio.mid),
            .float(audio.high),
            .float3(audio.bandTime.x, audio.bandTime.y, audio.bandTime.z),
            .float2(proxy.size),
          ])
        )
    }
  }
}

extension View {
  func audioColorEffect(_ function: ShaderFunction, audio: SmoothedAudio) -> some View {
    modifier(AudioColorEffectShader(shaderFunction: function, audio: audio))
  }
}
