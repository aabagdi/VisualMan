//
//  AudioMetalView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

#if !targetEnvironment(simulator)
import SwiftUI
import MetalKit
import QuartzCore
import os

struct MetalViewConfig {
  var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
  var backgroundColor: UIColor?
  var maxFramesPerSecond: Int = 120
  var colorSpace: CGColorSpace?
  var pixelFormat: MTLPixelFormat = .bgra8Unorm
  var wantsExtendedDynamicRange: Bool = false
  var standardRangeColorSpace: CGColorSpace?
  var standardRangePixelFormat: MTLPixelFormat = .bgra8Unorm
}

struct AudioMetalView<R: MetalVisualizerRenderer>: View {
  let renderer: R
  let audioLevels: [1024 of Float]
  var config: MetalViewConfig = MetalViewConfig()

  var body: some View {
    AudioCAMetalLayerView(renderer: renderer, audioLevels: audioLevels, config: config)
  }
}

#endif
