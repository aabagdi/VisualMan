//
//  MetalVisualizerRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

import Metal
import QuartzCore

@MainActor
protocol MetalVisualizerRenderer: AnyObject {
  var device: MTLDevice { get }
  var commandQueue: any MTL4CommandQueue { get }

  func canRenderThisFrame() -> Bool
  func encodeFrame(bass: Float, mid: Float, high: Float, drawableTexture: MTLTexture) -> MTLTexture?
  func commitFrame(intermediateTexture: MTLTexture, drawable: CAMetalDrawable)
  func reset()
  func prepareForResume()
}

extension MetalVisualizerRenderer {
  func canRenderThisFrame() -> Bool { true }
  func reset() {}
  func prepareForResume() {}
}
