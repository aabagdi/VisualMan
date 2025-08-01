//
//  View+JuliaShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func fireworksShader(time: Float, smoothedBass: Float, smoothedMid: Float, smoothedHigh: Float, peakLevel: Float) -> some View {
    modifier(FireworksShader(time: time, smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh, peakLevel: peakLevel))
  }
}

struct FireworksShader: ViewModifier {
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  var peakLevel: Float
  
  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          ShaderLibrary.fireworks(
            .float(time),
            .float(smoothedBass),
            .float(smoothedMid),
            .float(smoothedHigh),
            .float(peakLevel),
            .float2(proxy.size.width, proxy.size.height)
          )
        )
    }
  }
}
