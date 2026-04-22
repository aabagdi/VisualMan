//
//  LiquidLightVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

import SwiftUI
import MetalKit

struct LiquidLightVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    MetalVisualizerContainerView<LiquidLightRenderer>(
      audioLevels: audioLevels,
      config: MetalViewConfig(
        clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
        backgroundColor: .black),
      factory: { device in await LiquidLightRenderer.create(device: device) })
  }
}
