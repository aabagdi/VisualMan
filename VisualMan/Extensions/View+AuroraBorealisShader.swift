//
//  View+AuroraBorealisShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

extension View {
  func auroraBorealisShader(time: Float,
                            smoothedBass: Float,
                            smoothedMid: Float,
                            smoothedHigh: Float) -> some View {
    modifier(AuroraBorealisShader(time: time,
                                  smoothedBass: smoothedBass,
                                  smoothedMid: smoothedMid,
                                  smoothedHigh: smoothedHigh))
  }
}

struct AuroraBorealisShader: ViewModifier {
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  
  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          ShaderLibrary.auroraBorealis(
            .float(time),
            .float(smoothedBass),
            .float(smoothedMid),
            .float(smoothedHigh),
            .float2(proxy.size)
          )
        )
    }
  }
}
