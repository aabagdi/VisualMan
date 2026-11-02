//
//  AbstractExpressionismRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

extension AbstractExpressionismRenderer {
  struct Pipelines {
    let paint: MTLComputePipelineState
    let compose: MTLComputePipelineState
    let velocity: MTLComputePipelineState
    let resample: MTLComputePipelineState
    let pigment: MTLComputePipelineState
  }

  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else {
      logger.error("Failed to create default Metal library")
      return nil
    }
    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      Self.makePipeline(name, library: library, compiler: compiler)
    }
    guard let paint        = makePipeline("abexPaint"),
          let compose      = makePipeline("abexCompose"),
          let velocity     = makePipeline("abexVelocityDeposit"),
          let resample     = makePipeline("abexResample"),
          let pigment      = makePipeline("abexPigment") else { return nil }
    return Pipelines(paint: paint, compose: compose, velocity: velocity,
                     resample: resample, pigment: pigment)
  }

  static func createArgumentTables(device: MTLDevice) -> [any MTL4ArgumentTable]? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 10
    desc.maxBufferBindCount = 5
    var tables = [any MTL4ArgumentTable]()
    for _ in 0..<maxFramesInFlight {
      do {
        tables.append(try device.makeArgumentTable(descriptor: desc))
      } catch {
        logger.error("Failed to create argument table: \(error.localizedDescription)")
        return nil
      }
    }
    return tables
  }

  func configureResidencySet() {
    for buf in uniformBuffers { residencySet.addAllocation(buf) }
    if let lut = mixboxLUT {
      residencySet.addAllocation(lut)
    }
    if let cracks = crackTexture {
      residencySet.addAllocation(cracks)
    }
    residencySet.commit()
    commandQueue.addResidencySet(residencySet)
  }
}

#endif
