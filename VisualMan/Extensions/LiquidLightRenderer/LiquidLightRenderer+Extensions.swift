//
//  LiquidLightRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/7/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

extension LiquidLightRenderer {
  struct Pipelines {
    let seed: MTLComputePipelineState
    let resample: MTLComputePipelineState
    let advect: MTLComputePipelineState
    let reduceTiles: MTLComputePipelineState
    let reduceFinal: MTLComputePipelineState
    let relax: MTLComputePipelineState
    let probe: MTLComputePipelineState
    let render: MTLComputePipelineState
    let feedback: MTLComputePipelineState
    let blur: MTLComputePipelineState
  }

  nonisolated static func createPipelines(device: MTLDevice, compiler: any MTL4Compiler) -> Pipelines? {
    guard let library = device.makeDefaultLibrary() else {
      logger.error("Failed to create default Metal library")
      return nil
    }

    func makePipeline(_ name: String) -> MTLComputePipelineState? {
      Self.makePipeline(name, library: library, compiler: compiler)
    }

    guard let seedPipeline = makePipeline("liquidSimSeed"),
          let resamplePipeline = makePipeline("liquidSimResample"),
          let advectPipeline = makePipeline("liquidSimAdvect"),
          let reduceTilesPipeline = makePipeline("liquidSimReduceTiles"),
          let reduceFinalPipeline = makePipeline("liquidSimReduceFinal"),
          let relaxPipeline = makePipeline("liquidSimRelax"),
          let probePipeline = makePipeline("liquidSimProbe"),
          let renderPipeline = makePipeline("liquidLightRender"),
          let feedbackPipeline = makePipeline("liquidLightFeedback"),
          let blurPipeline = makePipeline("liquidGlassBlur") else {
      return nil
    }

    return Pipelines(seed: seedPipeline, resample: resamplePipeline, advect: advectPipeline,
                     reduceTiles: reduceTilesPipeline, reduceFinal: reduceFinalPipeline,
                     relax: relaxPipeline, probe: probePipeline, render: renderPipeline,
                     feedback: feedbackPipeline, blur: blurPipeline)
  }

  static func createArgumentTables(device: MTLDevice) -> [any MTL4ArgumentTable]? {
    let desc = MTL4ArgumentTableDescriptor()
    desc.maxTextureBindCount = 3
    desc.maxBufferBindCount = 3
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
    residencySet.addAllocation(reduceTilesBuffer)
    residencySet.addAllocation(lambdaBuffer)
    residencySet.addAllocation(probeBuffer)
    residencySet.commit()
    commandQueue.addResidencySet(residencySet)
  }
}

#endif
