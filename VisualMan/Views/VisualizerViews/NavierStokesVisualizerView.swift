//
//  NavierStokesVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct NavierStokesVisualizerView: View {
  @State private var renderer: NavierStokesRenderer?
  @State private var smoothedBass: Float = 0
  @State private var smoothedMid: Float = 0
  @State private var smoothedHigh: Float = 0
  
  let audioLevels: [1024 of Float]
  
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
    TimelineView(.animation) { timeline in
      Group {
        if let renderer {
          NavierStokesMetalView(renderer: renderer,
                         bass: smoothedBass,
                         mid: smoothedMid,
                         high: smoothedHigh)
        } else {
          Color.black
        }
      }
      .onChange(of: timeline.date) {
        // Asymmetric envelope: fast attack, slow release
        let bTarget = bassLevel
        let bSmooth: Float = bTarget > smoothedBass ? 0.2 : 0.85
        smoothedBass = smoothedBass * bSmooth + bTarget * (1.0 - bSmooth)
        
        let mTarget = midLevel
        let mSmooth: Float = mTarget > smoothedMid ? 0.25 : 0.8
        smoothedMid = smoothedMid * mSmooth + mTarget * (1.0 - mSmooth)
        
        let hTarget = highLevel
        let hSmooth: Float = hTarget > smoothedHigh ? 0.15 : 0.75
        smoothedHigh = smoothedHigh * hSmooth + hTarget * (1.0 - hSmooth)
      }
      .ignoresSafeArea()
    }
    .onAppear {
      renderer = NavierStokesRenderer()
    }
  }
}
