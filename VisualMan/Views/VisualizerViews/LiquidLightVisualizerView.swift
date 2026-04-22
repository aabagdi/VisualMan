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
  @State private var rendererFailed = false

  let audioLevels: [1024 of Float]

  var body: some View {
    ZStack {
      Color.black
      if let renderer {
        AudioMetalView(renderer: renderer,
                       audioLevels: audioLevels,
                       config: MetalViewConfig(
                           clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
                           backgroundColor: .black))
      } else if rendererFailed {
        ContentUnavailableView("Renderer Unavailable",
                               systemImage: "exclamationmark.triangle",
                               description: Text("Metal rendering is not available on this device."))
      } else {
        ProgressView()
      }
    }
    .ignoresSafeArea()
    .task {
      if let cached = cache.renderer(LiquidLightRenderer.self) {
        renderer = cached
      } else {
        renderer = await cache.renderer(LiquidLightRenderer.self) { await LiquidLightRenderer.create() }
      }
      if renderer == nil { rendererFailed = true }
    }
  }
}
