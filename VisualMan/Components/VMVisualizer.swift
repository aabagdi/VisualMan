//
//  Visualizer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/31/26.
//

import Observation

@Observable @MainActor
final class VisualizerSelection {
  var current: VMVisualizer = .bars
}

enum VMVisualizer: String, CaseIterable {
  case bars = "Bars"
  case threeD = "3D Bars"
  case album = "Album Art Waves"
  case julia = "Julia Set"
  case fireworks = "Fireworks"
  case interference = "Interference Pattern"
  case voronoi = "Voronoi Diagram"
  case aurora = "Aurora Borealis"
  case oscilloscope = "CRT Oscilloscope"
  case sphereMesh = "Sphere"
  case plasma = "Plasma"
  case metaball = "Lava Lamp"
  case ink = "Ink"
  case navierStokes = "Navier-Stokes"
  case liquidLight = "'60s Liquid Light"
  case gameOfLife = "LCD Game of Life"
  case abstractExpressionism = "Abstract Expressionism"
}
