//
//  DebugOverlay.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct DebugOverlay: View {
  var smoothedBass: Float
  var smoothedMid: Float
  var smoothedHigh: Float
  
  var body: some View {
    VStack(alignment: .leading) {
      Text("Bass: \(smoothedBass, specifier: "%.3f")")
      Text("Mid: \(smoothedMid, specifier: "%.3f")")
      Text("High: \(smoothedHigh, specifier: "%.3f")")
    }
    .padding()
    .background(.black.opacity(0.5))
    .foregroundColor(.white)
    .font(.caption)
  }
}
