//
//  NavierStokesVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI
import MetalKit

struct NavierStokesVisualizerView: View {
  @Environment(VisualizerRendererCache.self) private var cache
  @State private var renderer: NavierStokesRenderer?

  let audioLevels: [1024 of Float]

  var body: some View {
    ZStack {
      Color.black
      if let renderer {
        AudioMetalView(renderer: renderer,
                       audioLevels: audioLevels,
                       config: MetalViewConfig(
                           clearColor: MTLClearColor(red: 0, green: 0, blue: 0.02, alpha: 1)))
      }
    }
    .ignoresSafeArea()
    .task {
      if let cached = cache.renderer(NavierStokesRenderer.self) {
        renderer = cached
      } else {
        renderer = await cache.renderer(NavierStokesRenderer.self) { await NavierStokesRenderer.create() }
      }
    }
  }
}
