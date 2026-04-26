//
//  AbstractExpressionismVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

import SwiftUI
import MetalKit

struct AbstractExpressionismVisualizerView: View {
  let audioLevels: [1024 of Float]
  let isPlaying: Bool

  @Environment(VisualizerRendererCache.self) private var cache

  var body: some View {
    MetalVisualizerContainerView<AbstractExpressionismRenderer>(
      audioLevels: audioLevels,
      config: MetalViewConfig(
        clearColor: MTLClearColor(red: 0.95, green: 0.92, blue: 0.87, alpha: 1),
        backgroundColor: UIColor(red: 0.95, green: 0.92, blue: 0.87, alpha: 1)),
      factory: { [isPlaying] device in
        let renderer = await AbstractExpressionismRenderer.create(device: device)
        renderer?.isPlaying = isPlaying
        return renderer
      })
      .onChange(of: isPlaying, initial: true) { _, newValue in
        cache.renderer(AbstractExpressionismRenderer.self)?.isPlaying = newValue
      }
  }
}
