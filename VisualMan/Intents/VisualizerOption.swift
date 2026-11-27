//
//  VisualizerOption.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/26/26.
//

import AppIntents

nonisolated enum VisualizerOption: String, AppEnum {
  case bars
  case threeD
  case album
  case julia
  case fireworks
  case interference
  case voronoi
  case aurora
  case oscilloscope
  case plasma
  case metaball
  case navierStokes
  case liquidLight
  case gameOfLife
  case abstractExpressionism

  static let typeDisplayRepresentation: TypeDisplayRepresentation = "Visualizer"

  static let caseDisplayRepresentations: [VisualizerOption: DisplayRepresentation] = [
    .bars: "Bars",
    .threeD: "3D Bars",
    .album: "Album Art Waves",
    .julia: "Julia Set",
    .fireworks: "Fireworks",
    .interference: "Interference Pattern",
    .voronoi: "Voronoi Diagram",
    .aurora: "Aurora Borealis",
    .oscilloscope: "CRT Oscilloscope",
    .plasma: "Plasma",
    .metaball: DisplayRepresentation(title: "Lava Lamp", synonyms: ["Metaballs"]),
    .navierStokes: DisplayRepresentation(title: "Navier-Stokes", synonyms: ["Fluid", "Fluid Simulation"]),
    .liquidLight: DisplayRepresentation(title: "'60s Liquid Light", synonyms: ["Liquid Light", "Sixties Liquid Light"]),
    .gameOfLife: DisplayRepresentation(title: "LCD Game of Life", synonyms: ["Game of Life"]),
    .abstractExpressionism: DisplayRepresentation(title: "Abstract Expressionism", synonyms: ["AbEx", "Painting"]),
  ]
}

extension VisualizerOption {
  init(_ visualizer: VMVisualizer) {
    self = switch visualizer {
    case .bars: .bars
    case .threeD: .threeD
    case .album: .album
    case .julia: .julia
    case .fireworks: .fireworks
    case .interference: .interference
    case .voronoi: .voronoi
    case .aurora: .aurora
    case .oscilloscope: .oscilloscope
    case .plasma: .plasma
    case .metaball: .metaball
    case .navierStokes: .navierStokes
    case .liquidLight: .liquidLight
    case .gameOfLife: .gameOfLife
    case .abstractExpressionism: .abstractExpressionism
    }
  }

  var visualizer: VMVisualizer {
    switch self {
    case .bars: .bars
    case .threeD: .threeD
    case .album: .album
    case .julia: .julia
    case .fireworks: .fireworks
    case .interference: .interference
    case .voronoi: .voronoi
    case .aurora: .aurora
    case .oscilloscope: .oscilloscope
    case .plasma: .plasma
    case .metaball: .metaball
    case .navierStokes: .navierStokes
    case .liquidLight: .liquidLight
    case .gameOfLife: .gameOfLife
    case .abstractExpressionism: .abstractExpressionism
    }
  }
}
