//
//  MetalVisualizerContainerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

import SwiftUI
import MetalKit

struct MetalVisualizerContainerView<R: MetalVisualizerRenderer>: View {
  @Environment(VisualizerRendererCache.self) private var cache
  @State private var renderer: R?
  @State private var rendererFailed = false

  let audioLevels: [1024 of Float]
  let config: MetalViewConfig
  let factory: @MainActor (MTLDevice) async -> R?

  var body: some View {
    let resolved = renderer ?? cache.renderer(R.self)
    ZStack {
      Color.black
      if let resolved {
        AudioMetalView(renderer: resolved,
                       audioLevels: audioLevels,
                       config: config)
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
      guard renderer == nil else { return }
      if let cached = cache.renderer(R.self) {
        renderer = cached
      } else {
        renderer = await cache.renderer(R.self) {
          guard let device = cache.sharedDevice ?? MTLCreateSystemDefaultDevice() else { return nil }
          return await factory(device)
        }
      }
      if renderer == nil { rendererFailed = true }
    }
  }
}
