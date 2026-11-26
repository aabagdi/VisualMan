//
//  AbstractExpressionismRenderer+Film.swift
//  VisualMan
//
//  Created on 11/25/26.
//

#if !targetEnvironment(simulator)
import Metal
import simd

extension AbstractExpressionismRenderer {
  func renderFilm(encoder: any MTL4ComputeCommandEncoder,
                  heightWet: MTLTexture, flux: MTLTexture, base: MTLTexture,
                  params: AbExParams, region: CanvasRegion) {
    let cells = region.halved
    guard cells.width > 0, cells.height > 0 else { return }
    let x0 = max(cells.x - 1, 0)
    let y0 = max(cells.y - 1, 0)
    let x1 = cells.x + cells.width
    let y1 = cells.y + cells.height
    let bounds = SIMD4<UInt32>(UInt32(cells.x), UInt32(cells.y), UInt32(x1), UInt32(y1))

    encoder.setComputePipelineState(filmPipeline)
    argumentTable.setTexture(heightWet.gpuResourceID, index: 0)
    argumentTable.setTexture(flux.gpuResourceID, index: 1)
    argumentTable.setTexture(base.gpuResourceID, index: 2)
    argumentTable.setAddress(writeUniform(params), index: 0)
    argumentTable.setAddress(writeUniform(SIMD2<UInt32>(UInt32(x0), UInt32(y0))), index: 1)
    argumentTable.setAddress(writeUniform(bounds), index: 2)
    dispatch(encoder: encoder, pipeline: filmPipeline, width: x1 - x0, height: y1 - y0)
  }
}

#endif
