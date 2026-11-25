//
//  LiquidLightVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

#if !targetEnvironment(simulator)
import SwiftUI
import MetalKit

struct LiquidLightVisualizerView: View {
  private static let config = MetalViewConfig(
    clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
    backgroundColor: .black,
    colorSpace: LiquidLightRenderer.outputColorSpace,
    pixelFormat: LiquidLightRenderer.outputPixelFormat,
    wantsExtendedDynamicRange: LiquidLightRenderer.outputExtendedRange,
    standardRangeColorSpace: LiquidLightRenderer.standardRangeColorSpace,
    standardRangePixelFormat: LiquidLightRenderer.standardRangePixelFormat)

  var body: some View {
    MetalVisualizerContainerView(
      config: Self.config,
      factory: { device in await LiquidLightRenderer.create(device: device) })
  }
}

#endif
