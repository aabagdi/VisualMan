//
//  View+InterferenceShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func interferenceShader(time: Float, smoothedBass: Float, smoothedMid: Float, smoothedHigh: Float) -> some View {
    modifier(InterferenceShader(time: time, smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh))
  }
}

struct InterferenceShader: ViewModifier {
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  
  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          ShaderLibrary.interference(
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
