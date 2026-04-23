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

  static func createAllocatorsAndBuffers(device: MTLDevice)
    -> (allocators: [any MTL4CommandAllocator], buffers: [MTLBuffer])? {
    var allocators = [any MTL4CommandAllocator]()
    var buffers = [MTLBuffer]()
    for _ in 0..<maxFramesInFlight {
      guard let allocator = device.makeCommandAllocator(),
            let buffer = device.makeBuffer(length: uniformBufferSize, options: .storageModeShared) else {
        return nil
      }
      allocators.append(allocator)
      buffers.append(buffer)
    }
    return (allocators, buffers)
  }

  nonisolated static func makePipeline(
    _ name: String, library: MTLLibrary, compiler: any MTL4Compiler
  ) -> MTLComputePipelineState? {
    let functionDesc = MTL4LibraryFunctionDescriptor()
    functionDesc.name = name
    functionDesc.library = library
    let pipelineDesc = MTL4ComputePipelineDescriptor()
    pipelineDesc.computeFunctionDescriptor = functionDesc
    do {
      return try compiler.makeComputePipelineState(descriptor: pipelineDesc)
    } catch {
      rendererLogger.error("Failed to create pipeline '\(name)': \(error.localizedDescription)")
      return nil
    }
  }

  func drainPendingReleases(_ releases: inout [(frame: UInt64, texture: MTLTexture)]) {
    guard !releases.isEmpty else { return }
    let signaled = sharedEvent.signaledValue
    var removedAny = false
    releases.removeAll { entry in
      if signaled >= entry.frame {
        residencySet.removeAllocation(entry.texture)
        removedAny = true
        return true
      }
      return false
    }
    if removedAny {
      residencySet.commit()
    }
  }

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
    let stride = MemoryLayout<T>.stride
    let end = aligned + stride
    guard end <= Self.uniformBufferSize else {
      assertionFailure("Uniform buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      rendererLogger.error("Uniform buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      let fallbackAligned = (0 + 15) & ~15
      (currentUniformBuffer.contents() + fallbackAligned).storeBytes(of: value, as: T.self)
      uniformOffset = fallbackAligned + stride
      return currentUniformBuffer.gpuAddress + MTLGPUAddress(fallbackAligned)
    }
    (currentUniformBuffer.contents() + aligned).storeBytes(of: value, as: T.self)
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

  func writeUniformArray<T>(_ values: [T]) -> MTLGPUAddress {
    values.withUnsafeBufferPointer { buf in
      writeUniformArray(buf)
    }
  }

  func writeUniformArray<T>(_ values: UnsafeBufferPointer<T>) -> MTLGPUAddress {
    let aligned = (uniformOffset + 15) & ~15
    let size = MemoryLayout<T>.stride * values.count
    let end = aligned + size
    guard end <= Self.uniformBufferSize else {
      assertionFailure("Uniform array buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      rendererLogger.error("Uniform array buffer overflow: need \(end) bytes, have \(Self.uniformBufferSize)")
      let clampedSize = min(size, Self.uniformBufferSize)
      if let baseAddress = values.baseAddress, clampedSize > 0 {
        memcpy(currentUniformBuffer.contents(), baseAddress, clampedSize)
      }
      uniformOffset = clampedSize
      return currentUniformBuffer.gpuAddress
    }
    let ptr = currentUniformBuffer.contents() + aligned
    if let baseAddress = values.baseAddress {
      memcpy(ptr, baseAddress, size)
    }
    let addr = currentUniformBuffer.gpuAddress + MTLGPUAddress(aligned)
    uniformOffset = end
    return addr
  }

  func beginFrame() -> (any MTL4ComputeCommandEncoder)? {
    guard canRenderThisFrame() else { return nil }
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
