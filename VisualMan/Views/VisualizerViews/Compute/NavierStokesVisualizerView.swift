//
//  NavierStokesVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

#if !targetEnvironment(simulator)
import SwiftUI
import Metal

struct NavierStokesVisualizerView: View {
  @Environment(VisualizerSelection.self) private var visualizerSelection

  private static let config = MetalViewConfig(
    clearColor: MTLClearColor(red: 0, green: 0, blue: 0.0015, alpha: 1),
    pacesFrameRate: true,
    colorSpace: NavierStokesRenderer.outputColorSpace,
    pixelFormat: NavierStokesRenderer.outputPixelFormat,
    wantsExtendedDynamicRange: NavierStokesRenderer.outputExtendedRange,
    standardRangeColorSpace: NavierStokesRenderer.standardRangeColorSpace,
    standardRangePixelFormat: NavierStokesRenderer.standardRangePixelFormat)

  var body: some View {
    MetalVisualizerContainerView(
      config: Self.config,
      configuration: visualizerSelection.navierStokesSolver,
      configure: { renderer, solver in renderer.solver = solver },
      factory: { device in await NavierStokesRenderer.create(device: device) })
  }
}

#endif
