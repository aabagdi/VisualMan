//
//  View+AudioColorEffect.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import SwiftUI

struct AudioColorEffectShader: ViewModifier {
  let shaderFunction: ShaderFunction
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float

  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          Shader(function: shaderFunction, arguments: [
            .float(time),
            .float(smoothedBass),
            .float(smoothedMid),
            .float(smoothedHigh),
            .float2(proxy.size)
          ])
        )
    }
  }
}

extension View {
  func audioColorEffect(_ function: ShaderFunction,
                        time: Float,
                        smoothedBass: Float,
                        smoothedMid: Float,
                        smoothedHigh: Float) -> some View {
    modifier(AudioColorEffectShader(
      shaderFunction: function,
      time: time,
      smoothedBass: smoothedBass,
      smoothedMid: smoothedMid,
      smoothedHigh: smoothedHigh))
  }
}
