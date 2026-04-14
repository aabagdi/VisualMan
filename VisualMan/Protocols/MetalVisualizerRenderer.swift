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
  var dt: Float { get set }

  func update(bass: Float, mid: Float, high: Float, drawable: CAMetalDrawable)
  func reset()
  func prepareForResume()
}

extension MetalVisualizerRenderer {
  func reset() {}
  func prepareForResume() {}
}
