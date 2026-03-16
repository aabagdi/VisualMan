//
//  NavierStokesRenderer+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/15/26.
//

import Metal
import simd

extension NavierStokesRenderer {
  func injectAudioSplats(encoder: any MTL4ComputeCommandEncoder,
                         bass: Float,
                         mid: Float,
                         high: Float) {
    let center = Float(gridSize) * 0.5
    let gs = Float(gridSize)
    
    if bass > 0.01 {
      injectBassSplats(encoder: encoder, bass: bass, center: center, gs: gs)
    }
    if mid > 0.01 {
      injectMidSplats(encoder: encoder, mid: mid, center: center, gs: gs)
    }
    if high > 0.02 {
      injectHighSplats(encoder: encoder, high: high, center: center, gs: gs)
    }
    
    prevBass = bass
    prevMid = mid
  }
  
  private func injectBassSplats(encoder: any MTL4ComputeCommandEncoder,
                                bass: Float, center: Float, gs: Float) {
    let bassForce = bass * 300.0
    let bassRadius = gs * 0.08 * (1.0 + bass * 0.5)
    
    let bassOnset = max(bass - prevBass, 0)
    let onsetBoost = 1.0 + bassOnset * 5.0
    
    let angle1 = time * 0.7
    let angle2 = angle1 + .pi
    let orbitRadius = gs * 0.15
    
    let pos1 = SIMD2<Float>(center + cos(angle1) * orbitRadius,
                            center + sin(angle1) * orbitRadius)
    let pos2 = SIMD2<Float>(center + cos(angle2) * orbitRadius,
                            center + sin(angle2) * orbitRadius)
    
    let dir1 = normalize(pos1 - SIMD2<Float>(center, center))
    let dir2 = normalize(pos2 - SIMD2<Float>(center, center))
    
    let force1 = SIMD3<Float>(dir1.x, dir1.y, 0) * bassForce * onsetBoost
    let force2 = SIMD3<Float>(dir2.x, dir2.y, 0) * bassForce * onsetBoost
    
    splatForce(encoder: encoder, pos: pos1, force: force1, radius: bassRadius)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    splatForce(encoder: encoder, pos: pos2, force: force2, radius: bassRadius)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    let bassColor = SIMD3<Float>(bass * 1.5, bass * 0.3, bass * 0.8) * onsetBoost
    splatDye(encoder: encoder, pos: pos1, color: bassColor, radius: bassRadius * 1.2)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    splatDye(encoder: encoder, pos: pos2, color: bassColor * 0.8, radius: bassRadius * 1.2)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }
  
  private func injectMidSplats(encoder: any MTL4ComputeCommandEncoder,
                               mid: Float, center: Float, gs: Float) {
    let midForce = mid * 200.0
    let midRadius = gs * 0.04 * (1.0 + mid * 0.3)
    
    let midOnset = max(mid - prevMid, 0)
    let midBoost = 1.0 + midOnset * 3.0
    
    for i in 0..<3 {
      let angle = time * 1.3 + Float(i) * (.pi * 2.0 / 3.0)
      let orbit = gs * 0.25
      let pos = SIMD2<Float>(center + cos(angle) * orbit,
                             center + sin(angle) * orbit)
      
      let tangent = SIMD2<Float>(-sin(angle), cos(angle))
      let force = SIMD3<Float>(tangent.x, tangent.y, 0) * midForce * midBoost
      
      splatForce(encoder: encoder, pos: pos, force: force, radius: midRadius)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      
      let hueShift = Float(i) * 0.33
      let midColor = SIMD3<Float>(mid * 0.2 * (1.0 + hueShift),
                                  mid * 1.2,
                                  mid * (0.5 + hueShift)) * midBoost
      splatDye(encoder: encoder, pos: pos, color: midColor, radius: midRadius * 1.3)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }
  
  private func injectHighSplats(encoder: any MTL4ComputeCommandEncoder,
                                high: Float, center: Float, gs: Float) {
    let highForce = high * 120.0
    let highRadius = gs * 0.02
    
    for i in 0..<4 {
      let angle = time * 2.1 + Float(i) * (.pi * 0.5) + sin(time * 3.0 + Float(i)) * 0.5
      let orbit = gs * 0.35
      let pos = SIMD2<Float>(center + cos(angle) * orbit,
                             center + sin(angle) * orbit)
      
      let dir = SIMD2<Float>(cos(angle + Float(i)), sin(angle + Float(i)))
      let force = SIMD3<Float>(dir.x, dir.y, 0) * highForce
      
      splatForce(encoder: encoder, pos: pos, force: force, radius: highRadius)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      
      let highColor = SIMD3<Float>(high * 0.5, high * 0.7, high * 2.0)
      splatDye(encoder: encoder, pos: pos, color: highColor, radius: highRadius * 1.5)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }
  
  private func injectVortex(encoder: any MTL4ComputeCommandEncoder,
                            center: Float,
                            s: Float,
                            audioEnergy: Float) {
    let vortexAngle = time * 0.3
    let vortexR: Float = 80.0 * s
    let strength: Float = 20.0 * s * (0.3 + audioEnergy * 0.7)
    for i in 0..<2 {
      if i > 0 { encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch) }
      let a = vortexAngle + Float(i) * .pi
      let pos = SIMD2<Float>(center + cos(a) * vortexR, center + sin(a) * vortexR)
      splatForce(encoder: encoder,
                 pos: pos,
                 force: SIMD3<Float>(-sin(a) * strength, cos(a) * strength, 0),
                 radius: 100.0 * s)
    }
    let hue = fmod(time * 0.1, 1.0)
    let color = SIMD3<Float>(
      0.3 + 0.2 * sin(hue * .pi * 2.0),
      0.15 + 0.2 * sin(hue * .pi * 2.0 + 2.094),
      0.25 + 0.2 * sin(hue * .pi * 2.0 + 4.189)
    )
    splatDye(encoder: encoder,
             pos: SIMD2<Float>(center, center),
             color: color * (0.3 + audioEnergy * 0.7),
             radius: 90.0 * s)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
  }
  
  func splatForce(encoder: any MTL4ComputeCommandEncoder,
                  pos: SIMD2<Float>,
                  force: SIMD3<Float>,
                  radius: Float) {
    encoder.setComputePipelineState(splatPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniform(pos), index: 0)
    argumentTable.setAddress(writeUniform(force), index: 1)
    argumentTable.setAddress(writeUniform(radius), index: 2)
    dispatchGrid(encoder: encoder)
  }
  
  func splatDye(encoder: any MTL4ComputeCommandEncoder,
                pos: SIMD2<Float>,
                color: SIMD3<Float>,
                radius: Float) {
    encoder.setComputePipelineState(splatPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setAddress(writeUniform(pos), index: 0)
    argumentTable.setAddress(writeUniform(color), index: 1)
    argumentTable.setAddress(writeUniform(radius), index: 2)
    dispatchGrid(encoder: encoder)
  }
  
  func advect(encoder: any MTL4ComputeCommandEncoder,
              velocityIn: MTLTexture,
              fieldIn: MTLTexture,
              fieldOut: MTLTexture,
              dissipation: Float) {
    encoder.setComputePipelineState(advectPipeline)
    argumentTable.setTexture(velocityIn.gpuResourceID, index: 0)
    argumentTable.setTexture(fieldIn.gpuResourceID, index: 1)
    argumentTable.setTexture(fieldOut.gpuResourceID, index: 2)
    
    let dtVal = dt * 40.0
    argumentTable.setAddress(writeUniform(dtVal), index: 0)
    argumentTable.setAddress(writeUniform(dissipation), index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func computeVorticity(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(vorticityPipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(vorticityTexture.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder)
  }
  
  func applyVorticityForce(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(vorticityForcePipeline)
    argumentTable.setTexture(vorticityTexture.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    argumentTable.setAddress(writeUniform(vorticityStrength), index: 0)
    dispatchGrid(encoder: encoder)
  }
  
  func diffuseField(encoder: any MTL4ComputeCommandEncoder,
                    fieldA: inout MTLTexture!,
                    fieldB: inout MTLTexture!) {
    let alpha = viscosity * dt * Float(gridSize * gridSize)
    let rBeta = 1.0 / (1.0 + 4.0 * alpha)
    
    for _ in 0..<diffuseIterations {
      encoder.setComputePipelineState(diffusePipeline)
      argumentTable.setTexture(fieldA.gpuResourceID, index: 0)
      argumentTable.setTexture(fieldB.gpuResourceID, index: 1)
      argumentTable.setAddress(writeUniform(alpha), index: 0)
      argumentTable.setAddress(writeUniform(rBeta), index: 1)
      dispatchGrid(encoder: encoder)
      swap(&fieldA, &fieldB)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
  }
  
  func project(encoder: any MTL4ComputeCommandEncoder) {
    computeDivergence(encoder: encoder)
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    
    for _ in 0..<jacobiIterations {
      jacobiIteration(encoder: encoder)
      swap(&pressure, &pressureTemp)
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    }
    
    gradientSubtract(encoder: encoder)
  }
  
  func computeDivergence(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(divergencePipeline)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func jacobiIteration(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(jacobiPipeline)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(divergenceTexture.gpuResourceID, index: 1)
    argumentTable.setTexture(pressureTemp.gpuResourceID, index: 2)
    
    dispatchGrid(encoder: encoder)
  }
  
  func gradientSubtract(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(gradientSubtractPipeline)
    argumentTable.setTexture(pressure.gpuResourceID, index: 0)
    argumentTable.setTexture(velocityA.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func blurDyeH(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurHPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func blurDyeV(encoder: any MTL4ComputeCommandEncoder) {
    encoder.setComputePipelineState(blurVPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(dyeB.gpuResourceID, index: 1)
    
    dispatchGrid(encoder: encoder)
  }
  
  func render(encoder: any MTL4ComputeCommandEncoder, output: MTLTexture) {
    encoder.setComputePipelineState(renderPipeline)
    argumentTable.setTexture(dyeA.gpuResourceID, index: 0)
    argumentTable.setTexture(output.gpuResourceID, index: 1)
    dispatchGrid(encoder: encoder, width: output.width, height: output.height)
  }
  
  func dispatchGrid(encoder: any MTL4ComputeCommandEncoder, width: Int? = nil, height: Int? = nil) {
    let w = width ?? gridSize
    let h = height ?? gridSize
    let threadGroupSize = MTLSize(width: 16, height: 16, depth: 1)
    let threadGroups = MTLSize(
      width: (w + 15) / 16,
      height: (h + 15) / 16,
      depth: 1
    )
    encoder.dispatchThreadgroups(threadgroupsPerGrid: threadGroups,
                                 threadsPerThreadgroup: threadGroupSize)
  }
}
