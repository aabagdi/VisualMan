//
//  ThreeDBarsVisualizerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 8/1/25.
//

import SwiftUI
import RealityKit

struct ThreeDBarsVisualizerView: View {
  let visualizerBars: [32 of Float]
  @State private var model = ThreeDBarsVisualizerViewModel()

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      content.environment = .default
      content.add(await model.makeScene(barCount: visualizerBars.count))
    }
    .background(.black)
    .ignoresSafeArea()
    .accessibilityHidden(true)
    .gesture(orbitGesture)
    .gesture(zoomGesture)
    .onAppear {
      model.startSmoothing()
    }
    .onDisappear {
      model.stopSmoothing()
    }
    .onChange(of: visualizerBars) { _, newValues in
      model.targetValues = newValues
    }
  }

  private var orbitGesture: some Gesture {
    DragGesture()
      .onChanged { value in
        model.orbit(translation: value.translation)
      }
  }

  private var zoomGesture: some Gesture {
    MagnifyGesture()
      .onChanged { value in
        model.zoom(magnification: value.magnification)
      }
      .onEnded { _ in
        model.endZoom()
      }
  }
}
