//
//  MetalVisualizerRenderer.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

import Metal
import os
import QuartzCore

private nonisolated let rendererLogger = Logger(subsystem: "com.VisualMan", category: "MetalVisualizerRenderer")

@MainActor
protocol MetalVisualizerRenderer: AnyObject {
  var device: MTLDevice { get }
  var commandQueue: any MTL4CommandQueue { get }
  var commandBuffer: any MTL4CommandBuffer { get }
  var sharedEvent: MTLSharedEvent { get }
  var frameNumber: UInt64 { get set }
  var commandAllocators: [any MTL4CommandAllocator] { get }
  var uniformBuffers: [MTLBuffer] { get }
  var currentUniformBuffer: MTLBuffer { get set }
  var uniformOffset: Int { get set }
  var residencySet: MTLResidencySet { get }
  var argumentTable: any MTL4ArgumentTable { get }

  static var maxFramesInFlight: UInt64 { get }
  static var uniformBufferSize: Int { get }

  func encodeFrame(bass: Float, mid: Float, high: Float, drawableWidth: Int, drawableHeight: Int) -> MTLTexture?
  func commitFrame(drawable: CAMetalDrawable)
  func reset()
  func prepareForResume()
}

extension MetalVisualizerRenderer {
  func reset() {}
  func prepareForResume() {}

  func canRenderThisFrame() -> Bool {
    let nextFrame = frameNumber + 1
    if nextFrame > Self.maxFramesInFlight {
      let waitValue = nextFrame - Self.maxFramesInFlight
      return sharedEvent.signaledValue >= waitValue
    }
    return true
  }

  func writeUniform<T>(_ value: T) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let end = aligned + MemoryLayout<T>.size
    guard end <= Self.uniformBufferSize else {
      rendererLogger.error("Uniform buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      return currentUniformBuffer.gpuAddress
    }
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

  func writeUniformArray<T>(_ values: [T]) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let size = MemoryLayout<T>.stride * values.count
    let end = aligned + size
    guard end <= Self.uniformBufferSize else {
      rendererLogger.error("Uniform array buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      return currentUniformBuffer.gpuAddress
    }
    let ptr = currentUniformBuffer.contents() + aligned
    values.withUnsafeBufferPointer { buf in
      if let baseAddress = buf.baseAddress {
        memcpy(ptr, baseAddress, size)
      }
    }
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

  func beginFrame() -> (any MTL4ComputeCommandEncoder)? {
    frameNumber += 1
    let frameIndex = Int(frameNumber % Self.maxFramesInFlight)
    let allocator = commandAllocators[frameIndex]
    currentUniformBuffer = uniformBuffers[frameIndex]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return nil }
    encoder.setArgumentTable(argumentTable)
    return encoder
  }

  func commitFrame(drawable: CAMetalDrawable) {
    commandBuffer.endCommandBuffer()
    commandQueue.waitForDrawable(drawable)
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: frameNumber)
    commandQueue.signalDrawable(drawable)
    drawable.present()
  }
}
