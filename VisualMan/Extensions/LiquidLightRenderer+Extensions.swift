//
//  LiquidLightRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

import Metal
import os

private nonisolated let liquidLightLogger = Logger(subsystem: "com.VisualMan", category: "LiquidLightRenderer")

extension LiquidLightRenderer {
  struct Pipelines {
    let render: MTLComputePipelineState
    let blur: MTLComputePipelineState
  }

  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else {
      liquidLightLogger.error("Failed to create default Metal library")
      return nil
    }

    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      let functionDesc = MTL4LibraryFunctionDescriptor()
      functionDesc.name = name
      functionDesc.library = library
      let pipelineDesc = MTL4ComputePipelineDescriptor()
      pipelineDesc.computeFunctionDescriptor = functionDesc
      do {
        return try compiler.makeComputePipelineState(descriptor: pipelineDesc)
      } catch {
        liquidLightLogger.error("Failed to create pipeline '\(name)': \(error.localizedDescription)")
        return nil
      }
    }

    guard let renderPipeline = makePipeline("liquidLightRender"),
          let blurPipeline = makePipeline("liquidGlassBlur") else {
      return nil
    }

    return Pipelines(render: renderPipeline, blur: blurPipeline)
  }

  static func createAllocatorsAndBuffers(device: MTLDevice)
    -> (allocators: [any MTL4CommandAllocator], buffers: [MTLBuffer])? {
    var allocators: [any MTL4CommandAllocator] = []
    var buffers: [MTLBuffer] = []
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

  static func createArgumentTable(device: MTLDevice) -> (any MTL4ArgumentTable)? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 2
    desc.maxBufferBindCount = 1
    return try? device.makeArgumentTable(descriptor: desc)
  }

  func configureResidencySet() {
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    residencySet.commit()
    commandQueue.addResidencySet(residencySet)
  }
}
