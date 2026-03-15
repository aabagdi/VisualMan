//
//  NavierStokesMetalView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import SwiftUI
import MetalKit

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
    mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0.02, alpha: 1)
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
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
      renderer.ensureOutputTexture(width: Int(size.width), height: Int(size.height))
    }
    
    func draw(in view: MTKView) {
      guard let drawable = view.currentDrawable else { return }
      
      renderer.ensureOutputTexture(width: drawable.texture.width, height: drawable.texture.height)
      
      renderer.update(bass: bass, mid: mid, high: high)
      
      guard let commandBuffer = renderer.commandQueue.makeCommandBuffer(),
            let outputTexture = renderer.outputTexture,
            let blitEncoder = commandBuffer.makeBlitCommandEncoder() else { return }
      
      let srcSize = MTLSize(width: min(outputTexture.width, drawable.texture.width),
                            height: min(outputTexture.height, drawable.texture.height),
                            depth: 1)
      
      blitEncoder.copy(from: outputTexture,
                       sourceSlice: 0,
                       sourceLevel: 0,
                       sourceOrigin: MTLOrigin(x: 0, y: 0, z: 0),
                       sourceSize: srcSize,
                       to: drawable.texture,
                       destinationSlice: 0,
                       destinationLevel: 0,
                       destinationOrigin: MTLOrigin(x: 0, y: 0, z: 0))
      blitEncoder.endEncoding()
      
      commandBuffer.present(drawable)
      commandBuffer.commit()
    }
  }
}
