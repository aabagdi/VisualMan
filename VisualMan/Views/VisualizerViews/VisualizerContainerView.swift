//
//  VisualizerContainerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/31/26.
//

import SwiftUI

struct VisualizerContainerView: View {
  let currentVisualizer: VMVisualizer
  let visualizerBars: [32 of Float]
  let audioLevels: [1024 of Float]
  let waveform: [1024 of Float]
  let albumArt: UIImage?
  let isPlaying: Bool

  @Environment(VisualizerSnapshotter.self) private var snapshotter

  var body: some View {
    VisualizerSnapshotHost(snapshotter: snapshotter) {
      resolvedView
    }
  }

  private var resolvedView: AnyView {
    switch currentVisualizer {
    case .bars:
      return AnyView(BarsVisualizerView(visualizerBars: visualizerBars))
    case .threeD:
      return AnyView(ThreeDBarsVisualizerView(visualizerBars: visualizerBars))
    case .album:
      return AnyView(AlbumArtWaveVisualizerView(audioLevels: audioLevels, albumArt: albumArt))
    case .julia:
      return AnyView(JuliaVisualizerView(audioLevels: audioLevels))
    case .fireworks:
      return AnyView(FireworksVisualizerView(audioLevels: audioLevels))
    case .interference:
      return AnyView(InterferenceVisualizerView(audioLevels: audioLevels))
    case .voronoi:
      return AnyView(VoronoiVisualizerView(audioLevels: audioLevels))
    case .aurora:
      return AnyView(AuroraBorealisVisualizerView(audioLevels: audioLevels))
    case .oscilloscope:
      return AnyView(OscilloscopeVisualizerView(audioLevels: audioLevels, waveform: waveform))
    case .plasma:
      return AnyView(PlasmaVisualizerView(audioLevels: audioLevels))
    case .metaball:
      return AnyView(MetaballVisualizerView(audioLevels: audioLevels))
    #if targetEnvironment(simulator)
    case .navierStokes, .liquidLight, .gameOfLife, .abstractExpressionism:
      return AnyView(
        ContentUnavailableView("Not Available in Simulator",
                               systemImage: "cpu",
                               description: Text("This visualizer uses Metal 4. Run on a device to see it."))
          .background(Color.black)
          .ignoresSafeArea())
    #else
    case .navierStokes:
      return AnyView(NavierStokesVisualizerView(audioLevels: audioLevels))
    case .liquidLight:
      return AnyView(LiquidLightVisualizerView(audioLevels: audioLevels))
    case .gameOfLife:
      return AnyView(GameOfLifeVisualizerView(audioLevels: audioLevels))
    case .abstractExpressionism:
      return AnyView(AbstractExpressionismVisualizerView(audioLevels: audioLevels, isPlaying: isPlaying))
    #endif
    }
  }
}
