//
//  View+JuliaShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func juliaShader(time: Float, smoothedBass: Float, smoothedMid: Float, smoothedHigh: Float, width: Float, height: Float) -> some View {
    modifier(JuliaShader(time: time, smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh, width: width, height: height))
  }
}

struct JuliaShader: ViewModifier {
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  var width: Float
  var height: Float
  
  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          ShaderLibrary.julia(
            .float(time),
            .float(smoothedBass),
            .float(smoothedMid),
            .float(smoothedHigh),
            .float2(width, height)
          )
        )
    }
  }
}
