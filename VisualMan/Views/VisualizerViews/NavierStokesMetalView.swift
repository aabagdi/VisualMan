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
  let bass: Float
  let mid: Float
  let high: Float
  
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
    context.coordinator.bass = bass
    context.coordinator.mid = mid
    context.coordinator.high = high
  }
  
  func makeCoordinator() -> Coordinator {
    Coordinator(renderer: renderer)
  }
  
  @MainActor
  class Coordinator: NSObject, MTKViewDelegate {
    let renderer: NavierStokesRenderer
    var bass: Float = 0
    var mid: Float = 0
    var high: Float = 0
    
    init(renderer: NavierStokesRenderer) {
      self.renderer = renderer
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    
    func draw(in view: MTKView) {
      guard let drawable = view.currentDrawable else { return }
      renderer.update(bass: bass,
                      mid: mid,
                      high: high,
                      drawable: drawable)
    }
  }
}
