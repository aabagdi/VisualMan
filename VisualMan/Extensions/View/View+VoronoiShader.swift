//
//  View+VoronoiShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/29/25.
//

import SwiftUI

extension View {
  func voronoiShader(time: Float,
                     smoothedBass: Float,
                     smoothedMid: Float,
                     smoothedHigh: Float) -> some View {
    audioColorEffect(ShaderLibrary.voronoi,
                     time: time,
                     smoothedBass: smoothedBass,
                     smoothedMid: smoothedMid,
                     smoothedHigh: smoothedHigh)
  }
}
