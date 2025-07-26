//
//  CircleVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/26/25.
//

import SwiftUI

struct CircleVisualizerView: View {
  @State private var time: Float = 0
  @State private var smoothedBass: Float = 0
  @State private var smoothedMid: Float = 0
  @State private var smoothedHigh: Float = 0
  
  private var rainbow: some View {
    Image(systemName: "rainbow")
      .resizable()
      .aspectRatio(contentMode: .fit)
      .symbolRenderingMode(.multicolor)
  }
  
  let audioLevels: [Float]
  
  private var bassLevel: Float {
    guard audioLevels.count >= 512 else { return 0 }
    let bassRange = audioLevels[1..<10]
    return bassRange.reduce(0, +) / Float(bassRange.count)
  }
  
  private var midLevel: Float {
    guard audioLevels.count >= 512 else { return 0 }
    let midRange = audioLevels[10..<50]
    let midAvg = midRange.reduce(0, +) / Float(midRange.count)
    let midMax = midRange.max() ?? 0
    return midAvg * 0.5 + midMax * 0.5
  }
  
  private var highLevel: Float {
    guard audioLevels.count >= 512 else { return 0 }
    let highRange = audioLevels[50..<150]
    let highMax = highRange.max() ?? 0
    let highAvg = highRange.reduce(0, +) / Float(highRange.count)
    return highMax * 0.7 + highAvg * 0.3
  }
  
  var body: some View {
    GeometryReader { g in
      TimelineView(.animation) { timeline in
        Rectangle()
          .juliaShader(time: time, smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh, width: Float(g.size.width), height: Float(g.size.height))
          .onChange(of: timeline.date) {
            smoothedBass = smoothedBass * 0.5 + bassLevel * 0.5
            smoothedMid = smoothedMid * 0.6 + midLevel * 0.4
            smoothedHigh = smoothedHigh * 0.4 + highLevel * 0.6
            time += 0.016 * (1.0 + smoothedBass * 0.5)
          }
          .ignoresSafeArea()
      }
    }
    .overlay(alignment: .topTrailing) {
      // Debug overlay
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
}
