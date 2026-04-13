//
//  GameOfLifeVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

import SwiftUI
import MetalKit

struct GameOfLifeVisualizerView: View {
  @Environment(VisualizerRendererCache.self) private var cache
  @State private var renderer: GameOfLifeRenderer?

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
      }
    }
    .ignoresSafeArea()
    .task {
      if let cached = cache.renderer(GameOfLifeRenderer.self) {
        renderer = cached
      } else {
        renderer = await cache.renderer(GameOfLifeRenderer.self) { await GameOfLifeRenderer.create() }
      }
    }
  }
}
