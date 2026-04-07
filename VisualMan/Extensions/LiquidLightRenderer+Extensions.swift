//
//  LiquidLightRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

import Metal

extension LiquidLightRenderer {
  struct Pipelines {
    let render: MTLComputePipelineState
    let blur: MTLComputePipelineState
  }

  static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else { return nil }

    // Render pipeline
    let renderFuncDesc = MTL4LibraryFunctionDescriptor()
    renderFuncDesc.name = "liquidLightRender"
    renderFuncDesc.library = library
    let renderPipeDesc = MTL4ComputePipelineDescriptor()
    renderPipeDesc.computeFunctionDescriptor = renderFuncDesc
    guard let renderPipeline = try? compiler.makeComputePipelineState(descriptor: renderPipeDesc) else {
      return nil
    }

    // Blur pipeline
    let blurFuncDesc = MTL4LibraryFunctionDescriptor()
    blurFuncDesc.name = "liquidGlassBlur"
    blurFuncDesc.library = library
    let blurPipeDesc = MTL4ComputePipelineDescriptor()
    blurPipeDesc.computeFunctionDescriptor = blurFuncDesc
    guard let blurPipeline = try? compiler.makeComputePipelineState(descriptor: blurPipeDesc) else {
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
    desc.maxTextureBindCount = 2  // Pass 1 uses 1 texture, Pass 2 uses 2
    desc.maxBufferBindCount = 1
    return try? device.makeArgumentTable(descriptor: desc)
  }

  func configureResidencySet() {
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    residencySet.commit()
    commandQueue.addResidencySet(residencySet)
  }
}
