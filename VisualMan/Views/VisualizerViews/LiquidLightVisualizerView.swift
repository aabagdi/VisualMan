//
//  LiquidLightVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

import SwiftUI

struct LiquidLightVisualizerView: View {
  @State private var renderer: LiquidLightRenderer?

  let audioLevels: [1024 of Float]

  var body: some View {
    Group {
      if let renderer {
        LiquidLightMetalView(renderer: renderer,
                             audioLevels: audioLevels)
      } else {
        Color.black
      }
    }
    .ignoresSafeArea()
    .onAppear {
      renderer = LiquidLightRenderer()
    }
    .onDisappear {
      renderer = nil
    }
  }
}
