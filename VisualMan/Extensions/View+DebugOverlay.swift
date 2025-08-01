//
//  View+DebugOverlay.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

extension View {
  func debugOverlay(smoothedBass: Float, smoothedMid: Float, smoothedHigh: Float) -> some View {
    modifier(DebugOverlayModifier(smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh))
  }
}

struct DebugOverlayModifier: ViewModifier {
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  
  func body(content: Content) -> some View {
    content
      .overlay(alignment: .topTrailing) {
        DebugOverlay(smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh)
      }
  }
}
