//
//  VisualizerContainerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/31/26.
//

import SwiftUI

struct VisualizerContainerView: View {
  let currentVisualizer: VMVisualizer
  let albumArt: UIImage?
  let isPlaying: Bool

  @Environment(VisualizerSnapshotter.self) private var snapshotter

  var body: some View {
    VisualizerSnapshotHost(snapshotter: snapshotter) {
      resolvedView
    }
    .accessibilityIgnoresInvertColors()
  }

  @ViewBuilder
  private var resolvedView: some View {
    switch currentVisualizer {
    case .bars:
      BarsVisualizerView()
    case .threeD:
      ThreeDBarsVisualizerView()
    case .album:
      AlbumArtWaveVisualizerView(albumArt: albumArt)
    case .julia:
      JuliaVisualizerView()
    case .fireworks:
      FireworksVisualizerView()
    case .interference:
      InterferenceVisualizerView()
    case .voronoi:
      VoronoiVisualizerView()
    case .aurora:
      AuroraBorealisVisualizerView()
    case .oscilloscope:
      OscilloscopeVisualizerView()
    case .plasma:
      PlasmaVisualizerView()
    case .metaball:
      MetaballVisualizerView()
    #if targetEnvironment(simulator)
    case .navierStokes, .liquidLight, .gameOfLife, .abstractExpressionism:
      ContentUnavailableView("Not Available in Simulator",
                             systemImage: "cpu",
                             description: Text("This visualizer uses Metal 4. Run on a device to see it."))
        .background(Color.black)
        .ignoresSafeArea()
    #else
    case .navierStokes:
      NavierStokesVisualizerView()
    case .liquidLight:
      LiquidLightVisualizerView()
    case .gameOfLife:
      GameOfLifeVisualizerView()
    case .abstractExpressionism:
      AbstractExpressionismVisualizerView(isPlaying: isPlaying)
    #endif
    }
  }
}
