//
//  AbstractExpressionismRenderer+Textures.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/24/26.
//

import Metal

extension AbstractExpressionismRenderer {
  private static func makeCanvasDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeDisplayDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeHeightWetDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  func drainPendingTextureReleases() {
    drainPendingReleases(&pendingTextureReleases)
  }

  private func queueCurrentCanvasForRelease() {
    for old in [colorA, colorB, heightWetA, heightWetB] {
      if let t = old {
        pendingTextureReleases.append((frame: frameNumber, texture: t))
      }
    }
  }

  private func clearCanvasTextures() {
    colorA = nil; colorB = nil
    heightWetA = nil; heightWetB = nil
    canvasSize = 0
  }

  private func rebuildCanvasTextures(size: Int) -> Bool {
    queueCurrentCanvasForRelease()

    let colDesc = Self.makeCanvasDescriptor(width: size, height: size)
    let hwDesc = Self.makeHeightWetDescriptor(width: size, height: size)

    guard let cA = device.makeTexture(descriptor: colDesc),
          let cB = device.makeTexture(descriptor: colDesc),
          let hwA = device.makeTexture(descriptor: hwDesc),
          let hwB = device.makeTexture(descriptor: hwDesc) else {
      clearCanvasTextures()
      return false
    }

    for t in [cA, cB, hwA, hwB] {
      residencySet.addAllocation(t)
    }

    colorA = cA; colorB = cB
    heightWetA = hwA; heightWetB = hwB
    canvasSize = size
    isFirstFrame = true
    currentIsA = true
    return true
  }

  private func rebuildDisplayTexture(width: Int, height: Int) -> Bool {
    if let old = displayTex {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
    }
    let dispDesc = Self.makeDisplayDescriptor(width: width, height: height)
    guard let disp = device.makeTexture(descriptor: dispDesc) else {
      displayTex = nil
      lastDisplayWidth = 0; lastDisplayHeight = 0
      return false
    }
    residencySet.addAllocation(disp)
    displayTex = disp
    lastDisplayWidth = width
    lastDisplayHeight = height
    return true
  }

  func ensureCanvasTextures(displayWidth: Int, displayHeight: Int) -> Bool {
    let requestedCanvasSize = max(displayWidth, displayHeight)
    let targetCanvasSize = max(canvasSize, requestedCanvasSize)

    let canvasExists = colorA != nil && colorB != nil
        && heightWetA != nil && heightWetB != nil
    let canvasNeedsRebuild = !canvasExists || targetCanvasSize > canvasSize

    if canvasNeedsRebuild {
      guard rebuildCanvasTextures(size: targetCanvasSize) else { return false }
    }

    let displayNeedsRebuild = displayTex == nil
        || displayWidth != lastDisplayWidth
        || displayHeight != lastDisplayHeight

    if displayNeedsRebuild {
      guard rebuildDisplayTexture(width: displayWidth, height: displayHeight) else { return false }
    }

    if canvasNeedsRebuild || displayNeedsRebuild {
      residencySet.commit()
    }

    return true
  }

  private struct WarmUpTextures {
    let color: [MTLTexture]
    let heightWet: [MTLTexture]
    let display: MTLTexture
  }

  private func makeWarmUpTextures() -> WarmUpTextures? {
    let colDesc = Self.makeCanvasDescriptor(width: 64, height: 64)
    let hwDesc = Self.makeHeightWetDescriptor(width: 64, height: 64)
    let dispDesc = Self.makeDisplayDescriptor(width: 64, height: 64)

    guard let cA = device.makeTexture(descriptor: colDesc),
          let cB = device.makeTexture(descriptor: colDesc),
          let hwA = device.makeTexture(descriptor: hwDesc),
          let hwB = device.makeTexture(descriptor: hwDesc),
          let disp = device.makeTexture(descriptor: dispDesc) else { return nil }

    return WarmUpTextures(color: [cA, cB],
                          heightWet: [hwA, hwB],
                          display: disp)
  }

  func warmUpGPU() {
    guard let tex = makeWarmUpTextures() else { return }
    let dummies = tex.color + tex.heightWet + [tex.display]
    for t in dummies { residencySet.addAllocation(t) }
    residencySet.commit()

    let warmupFrame: UInt64 = 1
    let idx = Int(warmupFrame % Self.maxFramesInFlight)
    let allocator = commandAllocators[idx]
    currentUniformBuffer = uniformBuffers[idx]
    allocator.reset()
    uniformOffset = 0

    commandBuffer.beginCommandBuffer(allocator: allocator)
    commandBuffer.useResidencySet(residencySet)
    guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }
    encoder.setArgumentTable(argumentTable)

    let cc = Self.canvasColor
    let params = AbExParams(
      audio: .zero,
      canvas: SIMD4(cc.x, cc.y, cc.z, 0),
      config: SIMD4(0, 1, 0, 10),
      camera: SIMD4(0, 0, 1, 0),
      atmosphere: .zero)

    renderPaint(encoder: encoder,
                colorIn: tex.color[0], colorOut: tex.color[1],
                hwIn: tex.heightWet[0], hwOut: tex.heightWet[1],
                params: params, strokes: [])
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderCompose(encoder: encoder,
                  color: tex.color[1], heightWet: tex.heightWet[1],
                  output: tex.display, params: params)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: warmupFrame)
    frameNumber = warmupFrame

    sharedEvent.wait(untilSignaledValue: warmupFrame, timeoutMS: 1000)
    for t in dummies { residencySet.removeAllocation(t) }
    residencySet.commit()
  }
}
