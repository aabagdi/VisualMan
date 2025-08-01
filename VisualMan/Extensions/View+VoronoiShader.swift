//
//  View+VoronoiShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

extension View {
  func voronoiShader(time: Float, smoothedBass: Float, smoothedMid: Float, smoothedHigh: Float) -> some View {
    modifier(VoronoiShader(time: time, smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh))
  }
}

struct VoronoiShader: ViewModifier {
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  
  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .colorEffect(
          ShaderLibrary.voronoi(
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


