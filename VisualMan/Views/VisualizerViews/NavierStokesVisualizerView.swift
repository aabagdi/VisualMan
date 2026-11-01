//
//  NavierStokesVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#if !targetEnvironment(simulator)
import SwiftUI
import MetalKit

struct NavierStokesVisualizerView: View {
  let audioLevels: [1024 of Float]

  @Environment(VisualizerSelection.self) private var visualizerSelection
  @Environment(VisualizerRendererCache.self) private var cache

  var body: some View {
    MetalVisualizerContainerView<NavierStokesRenderer>(
      audioLevels: audioLevels,
      config: MetalViewConfig(
        clearColor: MTLClearColor(red: 0, green: 0, blue: 0.02, alpha: 1)),
      factory: { device in await NavierStokesRenderer.create(device: device) })
    .task(id: visualizerSelection.navierStokesProjectionMode) {
      let renderer = await cache.renderer(NavierStokesRenderer.self) {
        guard let device = cache.sharedDevice ?? MTLCreateSystemDefaultDevice() else { return nil }
        return await NavierStokesRenderer.create(device: device)
      }
      renderer?.projectionMode = visualizerSelection.navierStokesProjectionMode
    }
  }
}

#endif
