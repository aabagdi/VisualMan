//
//  GameOfLifeVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/12/26.
//

#if !targetEnvironment(simulator)
import SwiftUI
import Metal

struct GameOfLifeVisualizerView: View {
  private static let config = MetalViewConfig(
    clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1),
    backgroundColor: .black)

  var body: some View {
    MetalVisualizerContainerView(
      config: Self.config,
      factory: { device in await GameOfLifeRenderer.create(device: device) })
  }
}

#endif
