//
//  GameOfLifeVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

import SwiftUI
import MetalKit

struct GameOfLifeVisualizerView: View {
  let audioLevels: [1024 of Float]

  var body: some View {
    MetalVisualizerContainerView<GameOfLifeRenderer>(
      audioLevels: audioLevels,
      config: MetalViewConfig(
        clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
        backgroundColor: .black),
      factory: { device in await GameOfLifeRenderer.create(device: device) })
  }
}
