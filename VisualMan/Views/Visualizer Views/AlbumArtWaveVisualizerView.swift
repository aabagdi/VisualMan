//
//  AlbumArtWaveVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/31/25.
//

import SwiftUI

struct AlbumArtWaveVisualizerView: View {
  @State private var time: Float = 0
  @State private var smoothedBass: Float = 0
  @State private var smoothedMid: Float = 0
  @State private var smoothedHigh: Float = 0
  
  let audioLevels: [512 of Float]
  let albumArt: UIImage?
  let placeholder = UIImage(named: "Art Placeholder")!
  
  private var bassLevel: Float {
    guard audioLevels.count >= 512 else { return 0 }
    let bassRange = 1..<10
    var bassResult: Float = 0.0
    for i in bassRange { bassResult += audioLevels[i] }
    return bassResult / Float(bassRange.count)
  }
  
  private var midLevel: Float {
    guard audioLevels.count >= 512 else { return 0 }
    let midRange = 10..<50
    var midResult: Float = 0.0
    var midMax: Float = 0.0
    for i in midRange {
      let currentLevel = audioLevels[i]
      midMax = max(midMax, currentLevel)
      midResult += currentLevel
    }
    let midAvg = midResult / Float(midRange.count)
    return midAvg * 0.5 + midMax * 0.5
  }
  
  private var highLevel: Float {
    guard audioLevels.count >= 512 else { return 0 }
    let highRange = 50..<150
    var highResult: Float = 0.0
    var highMax: Float = 0.0
    for i in highRange {
      let currentLevel = audioLevels[i]
      highMax = max(highMax, currentLevel)
      highResult += currentLevel
    }
    let highAvg = highResult / Float(highRange.count)
    return highMax * 0.7 + highAvg * 0.3
  }
  
  var body: some View {
    GeometryReader { g in
      TimelineView(.animation) { timeline in
        Image(uiImage: albumArt ?? placeholder)
          .resizable()
          .scaledToFill()
          .scaleEffect(1.2)
          .frame(width: g.size.width, height: g.size.height)
          .albumArtWaveShader(time: time, smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh)
          .onChange(of: timeline.date) {
            withAnimation(.smooth) {
              smoothedBass = smoothedBass * 0.5 + bassLevel * 0.5
              smoothedMid = smoothedMid * 0.6 + midLevel * 0.4
              smoothedHigh = smoothedHigh * 0.4 + highLevel * 0.6
              time += 0.016 * (1.0 + smoothedBass * 0.5)
            }
          }
          .ignoresSafeArea()
      }
    }
    //.debugOverlay(smoothedBass: smoothedBass, smoothedMid: smoothedMid, smoothedHigh: smoothedHigh)
  }
}
