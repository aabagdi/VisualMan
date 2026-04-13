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
  let albumArt: UIImage?
  
  var body: some View {
    switch currentVisualizer {
    case .bars:
      BarsVisualizerView(visualizerBars: visualizerBars)
    case .threeD:
      ThreeDBarsVisualizerView(visualizerBars: visualizerBars)
    case .album:
      AlbumArtWaveVisualizerView(audioLevels: audioLevels, albumArt: albumArt)
    case .julia:
      JuliaVisualizerView(audioLevels: audioLevels)
    case .fireworks:
      FireworksVisualizerView(audioLevels: audioLevels)
    case .interference:
      InterferenceVisualizerView(audioLevels: audioLevels)
    case .voronoi:
      VoronoiVisualizerView(audioLevels: audioLevels)
    case .aurora:
      AuroraBorealisVisualizerView(audioLevels: audioLevels)
    case .oscilloscope:
      OscilloscopeVisualizerView(audioLevels: audioLevels)
    case .sphereMesh:
      SphereMeshVisualizerView(audioLevels: audioLevels)
    case .plasma:
      PlasmaVisualizerView(audioLevels: audioLevels)
    case .metaball:
      MetaballVisualizerView(audioLevels: audioLevels)
    case .ink:
      InkVisualizerView(audioLevels: audioLevels)
    case .navierStokes:
      NavierStokesVisualizerView(audioLevels: audioLevels)
    case .liquidLight:
      LiquidLightVisualizerView(audioLevels: audioLevels)
    case .gameOfLife:
      GameOfLifeVisualizerView(audioLevels: audioLevels)
    }
  }
}
