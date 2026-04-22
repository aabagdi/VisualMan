//
//  View+JuliaShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func juliaShader(time: Float,
                   smoothedBass: Float,
                   smoothedMid: Float,
                   smoothedHigh: Float) -> some View {
    audioColorEffect(ShaderLibrary.julia,
                     time: time,
                     smoothedBass: smoothedBass,
                     smoothedMid: smoothedMid,
                     smoothedHigh: smoothedHigh)
  }
}
