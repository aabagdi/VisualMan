//
//  AbstractExpressionismVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

#if !targetEnvironment(simulator)
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
      .overlay(alignment: .bottomLeading) {
        if AbstractExpressionismRenderer.paintTestEnabled {
          paintTestCaption
        }
      }
  }

  // Polls the renderer's current test step; the renderer is not observable,
  // so a periodic timeline keeps the caption in sync with the script.
  private var paintTestCaption: some View {
    TimelineView(.periodic(from: .now, by: 0.25)) { _ in
      Text(cache.renderer(AbstractExpressionismRenderer.self)?.paintTestStatus
           ?? "Paint test: waiting for renderer…")
        .font(.caption.monospaced())
        .foregroundStyle(.white)
        .padding(10)
        .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 8))
        .padding()
        .accessibilityHidden(true)
    }
  }
}

#endif
