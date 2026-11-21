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

  private static let clearColor: MTLClearColor = {
    let canvas = AbstractExpressionismRenderer.canvasColor
    return MTLClearColor(red: Double(canvas.x), green: Double(canvas.y), blue: Double(canvas.z), alpha: 1)
  }()

  var body: some View {
    MetalVisualizerContainerView<AbstractExpressionismRenderer>(
      audioLevels: audioLevels,
      config: MetalViewConfig(
        clearColor: Self.clearColor,
        backgroundColor: UIColor(red: 0.95, green: 0.92, blue: 0.87, alpha: 1),
        maxFramesPerSecond: 60,
        colorSpace: AbstractExpressionismRenderer.outputColorSpace,
        pixelFormat: AbstractExpressionismRenderer.outputPixelFormat,
        wantsExtendedDynamicRange: AbstractExpressionismRenderer.outputExtendedRange,
        standardRangeColorSpace: AbstractExpressionismRenderer.standardRangeColorSpace,
        standardRangePixelFormat: AbstractExpressionismRenderer.standardRangePixelFormat),
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
