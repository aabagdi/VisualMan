//
//  NavierStokesVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI

struct NavierStokesVisualizerView: View {
  @State private var renderer: NavierStokesRenderer?

  let audioLevels: [1024 of Float]

  var body: some View {
    Group {
      if let renderer {
        NavierStokesMetalView(renderer: renderer,
                              audioLevels: audioLevels)
      } else {
        Color.black
      }
    }
    .ignoresSafeArea()
    .onAppear {
      renderer = NavierStokesRenderer()
    }
  }
}
