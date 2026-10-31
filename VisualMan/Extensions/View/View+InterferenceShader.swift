//
//  View+InterferenceShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func interferenceShader(time: Float,
                          smoothedBass: Float,
                          smoothedMid: Float,
                          smoothedHigh: Float) -> some View {
    audioColorEffect(ShaderLibrary.interference,
                     time: time,
                     smoothedBass: smoothedBass,
                     smoothedMid: smoothedMid,
                     smoothedHigh: smoothedHigh)
  }
}
