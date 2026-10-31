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
    audioColorEffect(ShaderLibrary.auroraBorealis,
                     time: time,
                     smoothedBass: smoothedBass,
                     smoothedMid: smoothedMid,
                     smoothedHigh: smoothedHigh)
  }
}
