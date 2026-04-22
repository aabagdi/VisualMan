//
//  NavierStokesVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI
import MetalKit

struct NavierStokesVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    MetalVisualizerContainerView<NavierStokesRenderer>(
      audioLevels: audioLevels,
      config: MetalViewConfig(
        clearColor: MTLClearColor(red: 0, green: 0, blue: 0.02, alpha: 1)),
      factory: { device in await NavierStokesRenderer.create(device: device) })
  }
}
