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
      Self.makePipeline(name, library: library, compiler: compiler)
    }

    guard let renderPipeline = makePipeline("liquidLightRender"),
          let blurPipeline = makePipeline("liquidGlassBlur") else {
      return nil
    }

    return Pipelines(render: renderPipeline, blur: blurPipeline)
  }

  static func createArgumentTable(device: MTLDevice) -> (any MTL4ArgumentTable)? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 2
    desc.maxBufferBindCount = 1
    do {
      return try device.makeArgumentTable(descriptor: desc)
    } catch {
      liquidLightLogger.error("Failed to create argument table: \(error.localizedDescription)")
      return nil
    }
  }

  func configureResidencySet() {
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    residencySet.commit()
    commandQueue.addResidencySet(residencySet)
  }
}
