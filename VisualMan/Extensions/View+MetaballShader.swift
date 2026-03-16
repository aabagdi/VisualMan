//
//  View+MetaballShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

import SwiftUI

extension View {
  func metaballShader(time: Float,
                      smoothedBass: Float,
                      smoothedMid: Float,
                      smoothedHigh: Float) -> some View {
    modifier(MetaballShader(time: time,
                             smoothedBass: smoothedBass,
                             smoothedMid: smoothedMid,
                             smoothedHigh: smoothedHigh))
  }
}

struct MetaballShader: ViewModifier {
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  
  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          ShaderLibrary.metaball(
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
