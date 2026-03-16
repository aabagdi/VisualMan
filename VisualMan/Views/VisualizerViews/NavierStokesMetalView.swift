//
//  NavierStokesMetalView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI
import MetalKit
import QuartzCore

struct NavierStokesMetalView: UIViewRepresentable {
  let renderer: NavierStokesRenderer
  let audioLevels: [1024 of Float]

  func makeUIView(context: Context) -> MTKView {
    let mtkView = MTKView()
    mtkView.device = renderer.device
    mtkView.delegate = context.coordinator
    mtkView.preferredFramesPerSecond = 60
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.framebufferOnly = false
    mtkView.isPaused = false
    mtkView.enableSetNeedsDisplay = false
    mtkView.clearColor = MTLClearColor(red: 0,
                                        green: 0,
                                        blue: 0.02,
                                        alpha: 1)

    if let metalLayer = mtkView.layer as? CAMetalLayer {
      renderer.commandQueue.addResidencySet(metalLayer.residencySet)
    }

    return mtkView
  }

  func updateUIView(_ uiView: MTKView, context: Context) {
    context.coordinator.audioLevels = audioLevels
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(renderer: renderer)
  }

  @MainActor
  class Coordinator: NSObject, MTKViewDelegate {
    let renderer: NavierStokesRenderer
    var audioLevels: [1024 of Float] = .init(repeating: 0.0)
    private var smoothedBass: Float = 0
    private var smoothedMid: Float = 0
    private var smoothedHigh: Float = 0

    init(renderer: NavierStokesRenderer) {
      self.renderer = renderer
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
      guard let drawable = view.currentDrawable else { return }

      let bass = computeBass()
      let mid = computeMid()
      let high = computeHigh()

      let bSmooth: Float = bass > smoothedBass ? 0.2 : 0.85
      smoothedBass = smoothedBass * bSmooth + bass * (1.0 - bSmooth)

      let mSmooth: Float = mid > smoothedMid ? 0.25 : 0.8
      smoothedMid = smoothedMid * mSmooth + mid * (1.0 - mSmooth)

      let hSmooth: Float = high > smoothedHigh ? 0.15 : 0.75
      smoothedHigh = smoothedHigh * hSmooth + high * (1.0 - hSmooth)

      renderer.update(bass: smoothedBass,
                      mid: smoothedMid,
                      high: smoothedHigh,
                      drawable: drawable)
    }

    private func computeBass() -> Float {
      let bassRange = 1..<10
      var result: Float = 0.0
      for i in bassRange { result += audioLevels[i] }
      return result / Float(bassRange.count)
    }

    private func computeMid() -> Float {
      let midRange = 10..<50
      var result: Float = 0.0
      var peak: Float = 0.0
      for i in midRange {
        let level = audioLevels[i]
        peak = max(peak, level)
        result += level
      }
      return result / Float(midRange.count) * 0.5 + peak * 0.5
    }

    private func computeHigh() -> Float {
      let highRange = 50..<150
      var result: Float = 0.0
      var peak: Float = 0.0
      for i in highRange {
        let level = audioLevels[i]
        peak = max(peak, level)
        result += level
      }
      return peak * 0.7 + result / Float(highRange.count) * 0.3
    }
  }
}
