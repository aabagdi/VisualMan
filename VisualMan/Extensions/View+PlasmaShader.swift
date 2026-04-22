//
//  View+PlasmaShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/16/26.
//

import SwiftUI

extension View {
  func plasmaShader(time: Float,
                    smoothedBass: Float,
                    smoothedMid: Float,
                    smoothedHigh: Float) -> some View {
    audioColorEffect(ShaderLibrary.plasma,
                     time: time,
                     smoothedBass: smoothedBass,
                     smoothedMid: smoothedMid,
                     smoothedHigh: smoothedHigh)
  }
}
