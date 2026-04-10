//
//  LiquidLightVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

import SwiftUI
import MetalKit

struct LiquidLightVisualizerView: View {
  @Environment(VisualizerRendererCache.self) private var cache
  @State private var renderer: LiquidLightRenderer?

  let audioLevels: [1024 of Float]

  var body: some View {
    Group {
      if let renderer {
        AudioMetalView(renderer: renderer,
                       audioLevels: audioLevels,
                       config: MetalViewConfig(
                           clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
                           backgroundColor: .black))
      } else {
        Color.black
      }
    }
    .ignoresSafeArea()
    .onAppear {
      renderer = cache.renderer(LiquidLightRenderer.self) { LiquidLightRenderer() }
    }
  }
}
