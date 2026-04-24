//
//  AbstractExpressionismRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

import Metal
import os

extension AbstractExpressionismRenderer {
  struct Pipelines {
    let paint: MTLComputePipelineState
    let compose: MTLComputePipelineState
  }

  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else {
      logger.error("Failed to create default Metal library")
      return nil
    }
    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      Self.makePipeline(name, library: library, compiler: compiler)
    }
    guard let paint   = makePipeline("abexPaint"),
          let compose = makePipeline("abexCompose") else { return nil }
    return Pipelines(paint: paint, compose: compose)
  }

  static func createArgumentTables(device: MTLDevice) -> [any MTL4ArgumentTable]? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 10
    desc.maxBufferBindCount = 2
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
    residencySet.commit()
    commandQueue.addResidencySet(residencySet)
  }
}
