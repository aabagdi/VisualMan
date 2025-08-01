//
//  3DBarVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import SwiftUI
import Charts

struct BallsVisualizerView: View {
  let visualizerBars: [Float]
  let minBarHeight: CGFloat = 4
  
  var body: some View {
    Chart3D(Array(visualizerBars.enumerated()), id: \.0) { index, level in
      PointMark(
        x: .value("Index", index),
        y: .value("Level", level * 10),
        z: .value("Width", 10)
      )
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .chartZAxis(.hidden)
  }
}
