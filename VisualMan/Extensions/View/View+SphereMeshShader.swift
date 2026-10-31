//
//  View+SphereMeshShader.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

extension View {
  func sphereMeshShader(time: Float,
                        smoothedBass: Float,
                        smoothedMid: Float,
                        smoothedHigh: Float) -> some View {
    audioColorEffect(ShaderLibrary.sphereMesh,
                     time: time,
                     smoothedBass: smoothedBass,
                     smoothedMid: smoothedMid,
                     smoothedHigh: smoothedHigh)
  }
}
