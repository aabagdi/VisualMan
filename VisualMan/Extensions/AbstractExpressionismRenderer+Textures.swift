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
      pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeHeightBackDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .r16Float, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeHeightMFDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rg16Float, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  func drainPendingTextureReleases() {
    drainPendingReleases(&pendingTextureReleases)
  }

  private func queueCurrentCanvasForRelease() {
    for old in [colorBackA, colorBackB, colorMidA, colorMidB,
                colorFrontA, colorFrontB,
                heightBackA, heightBackB,
                heightMFA, heightMFB] {
      if let t = old {
        pendingTextureReleases.append((frame: frameNumber, texture: t))
      }
    }
  }

  private func clearCanvasTextures() {
    colorBackA = nil; colorBackB = nil
    colorMidA = nil;  colorMidB = nil
    colorFrontA = nil; colorFrontB = nil
    heightBackA = nil; heightBackB = nil
    heightMFA = nil;   heightMFB = nil
    canvasSize = 0
  }

  private func rebuildCanvasTextures(size: Int) -> Bool {
    queueCurrentCanvasForRelease()

    let colDesc = Self.makeCanvasDescriptor(width: size, height: size)
    let hbDesc = Self.makeHeightBackDescriptor(width: size, height: size)
    let hmfDesc = Self.makeHeightMFDescriptor(width: size, height: size)

    guard let bA = device.makeTexture(descriptor: colDesc),
          let bB = device.makeTexture(descriptor: colDesc),
          let mA = device.makeTexture(descriptor: colDesc),
          let mB = device.makeTexture(descriptor: colDesc),
          let fA = device.makeTexture(descriptor: colDesc),
          let fB = device.makeTexture(descriptor: colDesc),
          let hbA = device.makeTexture(descriptor: hbDesc),
          let hbB = device.makeTexture(descriptor: hbDesc),
          let hmfA = device.makeTexture(descriptor: hmfDesc),
          let hmfB = device.makeTexture(descriptor: hmfDesc) else {
      clearCanvasTextures()
      return false
    }

    for t in [bA, bB, mA, mB, fA, fB, hbA, hbB, hmfA, hmfB] {
      residencySet.addAllocation(t)
    }

    colorBackA   = bA;  colorBackB   = bB
    colorMidA    = mA;  colorMidB    = mB
    colorFrontA  = fA;  colorFrontB  = fB
    heightBackA  = hbA; heightBackB  = hbB
    heightMFA    = hmfA; heightMFB   = hmfB
    canvasSize   = size
    isFirstFrame = true
    currentIsA   = true
    return true
  }

  private func rebuildDisplayTexture(width: Int, height: Int) -> Bool {
    if let old = displayTex {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
    }
    let dispDesc = Self.makeCanvasDescriptor(width: width, height: height)
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

    let canvasExists = colorBackA != nil && colorBackB != nil
        && colorMidA != nil && colorMidB != nil
        && colorFrontA != nil && colorFrontB != nil
        && heightBackA != nil && heightBackB != nil
        && heightMFA != nil && heightMFB != nil
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
    let heightBack: [MTLTexture]
    let heightMF: [MTLTexture]
    let display: MTLTexture
  }

  private func makeWarmUpTextures() -> WarmUpTextures? {
    let colDesc = Self.makeCanvasDescriptor(width: 64, height: 64)
    let hbDesc = Self.makeHeightBackDescriptor(width: 64, height: 64)
    let hmfDesc = Self.makeHeightMFDescriptor(width: 64, height: 64)

    guard let bA = device.makeTexture(descriptor: colDesc),
          let bB = device.makeTexture(descriptor: colDesc),
          let mA = device.makeTexture(descriptor: colDesc),
          let mB = device.makeTexture(descriptor: colDesc),
          let fA = device.makeTexture(descriptor: colDesc),
          let fB = device.makeTexture(descriptor: colDesc),
          let hbA = device.makeTexture(descriptor: hbDesc),
          let hbB = device.makeTexture(descriptor: hbDesc),
          let hmfA = device.makeTexture(descriptor: hmfDesc),
          let hmfB = device.makeTexture(descriptor: hmfDesc),
          let disp = device.makeTexture(descriptor: colDesc) else { return nil }

    return WarmUpTextures(color: [bA, bB, mA, mB, fA, fB],
                          heightBack: [hbA, hbB],
                          heightMF: [hmfA, hmfB],
                          display: disp)
  }

  func warmUpGPU() {
    guard let tex = makeWarmUpTextures() else { return }
    let dummies = tex.color + tex.heightBack + tex.heightMF + [tex.display]
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
      camera: SIMD4(0, 0, 1, 0))

    renderPaint(encoder: encoder,
                colorBackIn: tex.color[0], colorBackOut: tex.color[1],
                colorMidIn: tex.color[2], colorMidOut: tex.color[3],
                colorFrontIn: tex.color[4], colorFrontOut: tex.color[5],
                heightBackIn: tex.heightBack[0], heightBackOut: tex.heightBack[1],
                heightMFIn: tex.heightMF[0], heightMFOut: tex.heightMF[1],
                params: params, strokes: [])
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderCompose(encoder: encoder,
                  colorBack: tex.color[1], colorMid: tex.color[3], colorFront: tex.color[5],
                  heightBack: tex.heightBack[1], heightMF: tex.heightMF[1],
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
