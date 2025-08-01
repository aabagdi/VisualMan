//
//  View+AlbumArtWaveShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/31/25.
//

import SwiftUI

extension View {
  func albumArtWaveShader(time: Float, smoothedBass: Float, smoothedMid: Float, smoothedHigh: Float) -> some View {
    modifier(AlbumArtWaveShader(time: time, smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh))
  }
}

struct AlbumArtWaveShader: ViewModifier {
  var time: Float
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float

  func body(content: Content) -> some View {
    content.visualEffect { content, proxy in
      content
        .distortionEffect(
          ShaderLibrary.albumArtWave(
            .float(time),
            .float(smoothedBass),
            .float(smoothedMid),
            .float(smoothedHigh),
            .float2(proxy.size)
          ), maxSampleOffset: .zero
        )
    }
  }
}
