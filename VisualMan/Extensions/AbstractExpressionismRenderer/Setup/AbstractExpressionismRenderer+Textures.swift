//
//  AbstractExpressionismRenderer+Textures.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/24/26.
//

#if !targetEnvironment(simulator)
import Metal
import CoreGraphics

extension AbstractExpressionismRenderer {
  static let outputExtendedRange = true
  static let standardRangePixelFormat: MTLPixelFormat = .bgra8Unorm_srgb
  static let standardRangeColorSpace = CGColorSpace(name: CGColorSpace.sRGB)
  static let outputPixelFormat: MTLPixelFormat = outputExtendedRange ? .rgba16Float : standardRangePixelFormat
  static let outputColorSpace = outputExtendedRange
    ? CGColorSpace(name: CGColorSpace.extendedLinearSRGB) : standardRangeColorSpace

  private static func makeCanvasDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeDisplayDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: width, height: height, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeHeightWetDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: width / 2, height: height / 2, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeDryColorDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: width / 2, height: height / 2, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  private static func makeVelocityDescriptor(width: Int, height: Int) -> MTLTextureDescriptor {
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba16Float, width: width / 2, height: height / 2, mipmapped: false)
    desc.usage = [.shaderRead, .shaderWrite]
    desc.storageMode = .private
    return desc
  }

  func drainPendingTextureReleases() {
    drainPendingReleases(&pendingTextureReleases)
  }

  private func queueCurrentCanvasForRelease(excluding: Set<ObjectIdentifier> = []) {
    for old in [colorA, colorB, heightWetA, heightWetB, colorMid, heightWetMid,
                velocityA, velocityB,
                dryColorA, dryColorB, dryColorMid, substrateMid,
                substrateA, substrateB, pigmentTexture, materialTexture] {
      if let t = old, !excluding.contains(ObjectIdentifier(t as AnyObject)) {
        pendingTextureReleases.append((frame: frameNumber, texture: t))
      }
    }
  }

  private func clearResampleSources() {
    for t in [resampleColorSrc, resampleHeightWetSrc,
              resampleDryColorSrc, resampleSubstrateSrc] {
      if let t { pendingTextureReleases.append((frame: frameNumber, texture: t)) }
    }
    resampleColorSrc = nil
    resampleHeightWetSrc = nil
    resampleDryColorSrc = nil
    resampleSubstrateSrc = nil
    pendingResample = false
  }

  private func clearCanvasTextures() {
    colorA = nil; colorB = nil
    heightWetA = nil; heightWetB = nil
    colorMid = nil; heightWetMid = nil
    velocityA = nil; velocityB = nil
    dryColorA = nil; dryColorB = nil; dryColorMid = nil
    substrateMid = nil
    substrateA = nil; substrateB = nil
    pigmentTexture = nil
    materialTexture = nil
    canvasSize = 0
  }

  private func captureResampleSources() -> Set<ObjectIdentifier> {
    let readA = currentIsA
    let cSrc  = readA ? colorA : colorB
    let hwSrc = readA ? heightWetA : heightWetB
    let dSrc  = readA ? dryColorA : dryColorB
    let sSrc  = readA ? substrateA : substrateB
    resampleColorSrc = cSrc
    resampleHeightWetSrc = hwSrc
    resampleDryColorSrc = dSrc
    resampleSubstrateSrc = sSrc
    var exclude: Set<ObjectIdentifier> = []
    for t in [cSrc, hwSrc, dSrc, sSrc] {
      if let t { exclude.insert(ObjectIdentifier(t as AnyObject)) }
    }
    return exclude
  }

  private func rebuildCanvasTextures(size: Int, preserveContent: Bool) -> Bool {
    let exclude = preserveContent ? captureResampleSources() : []
    queueCurrentCanvasForRelease(excluding: exclude)

    let colDesc = Self.makeCanvasDescriptor(width: size, height: size)
    let hwDesc = Self.makeHeightWetDescriptor(width: size, height: size)
    let velDesc = Self.makeVelocityDescriptor(width: size, height: size)
    let dryDesc = Self.makeDryColorDescriptor(width: size, height: size)
    let subDesc = dryDesc

    guard let cA = device.makeTexture(descriptor: colDesc),
          let cB = device.makeTexture(descriptor: colDesc),
          let cMid = device.makeTexture(descriptor: colDesc),
          let hwA = device.makeTexture(descriptor: hwDesc),
          let hwB = device.makeTexture(descriptor: hwDesc),
          let hwMid = device.makeTexture(descriptor: hwDesc),
          let vA = device.makeTexture(descriptor: velDesc),
          let vB = device.makeTexture(descriptor: velDesc),
          let dcA = device.makeTexture(descriptor: dryDesc),
          let dcB = device.makeTexture(descriptor: dryDesc),
          let dcMid = device.makeTexture(descriptor: dryDesc),
          let sA = device.makeTexture(descriptor: subDesc),
          let sB = device.makeTexture(descriptor: subDesc),
          let sMid = device.makeTexture(descriptor: subDesc),
          let pig = device.makeTexture(descriptor: colDesc),
          let mat = device.makeTexture(descriptor: colDesc) else {
      clearResampleSources()
      clearCanvasTextures()
      return false
    }

    for t in [cA, cB, cMid, hwA, hwB, hwMid, vA, vB,
              dcA, dcB, dcMid, sA, sB, sMid, pig, mat] {
      residencySet.addAllocation(t)
    }

    colorA = cA; colorB = cB; colorMid = cMid
    heightWetA = hwA; heightWetB = hwB; heightWetMid = hwMid
    velocityA = vA; velocityB = vB
    dryColorA = dcA; dryColorB = dcB; dryColorMid = dcMid
    substrateMid = sMid
    substrateA = sA; substrateB = sB
    pigmentTexture = pig
    materialTexture = mat
    pigmentFullRefreshFrames = 3
    canvasSize = size
    isFirstFrame = !preserveContent
    pendingResample = preserveContent
    currentIsA = true
    return true
  }

  private func rebuildDisplayTexture(width: Int, height: Int) -> Bool {
    for old in displayTextures {
      pendingTextureReleases.append((frame: frameNumber, texture: old))
    }
    let dispDesc = Self.makeDisplayDescriptor(width: width, height: height)
    guard let dispA = device.makeTexture(descriptor: dispDesc),
          let dispB = device.makeTexture(descriptor: dispDesc) else {
      displayTextures = []
      lastDisplayWidth = 0; lastDisplayHeight = 0
      return false
    }
    residencySet.addAllocation(dispA)
    residencySet.addAllocation(dispB)
    displayTextures = [dispA, dispB]
    lastDisplayWidth = width
    lastDisplayHeight = height
    return true
  }

  func ensureCanvasTextures(displayWidth: Int, displayHeight: Int) -> Bool {
    let scaledF = Float(max(displayWidth, displayHeight)) * Self.canvasRenderScale
    let scaled = max(2, Int(scaledF.rounded()))
    let requestedCanvasSize = scaled - (scaled % 2)

    let canvasExists = colorA != nil && colorB != nil && colorMid != nil
        && heightWetA != nil && heightWetB != nil && heightWetMid != nil
        && velocityA != nil && velocityB != nil
        && dryColorA != nil && dryColorB != nil && dryColorMid != nil
        && substrateMid != nil
        && substrateA != nil && substrateB != nil && pigmentTexture != nil
        && materialTexture != nil

    let grow = requestedCanvasSize > canvasSize
    let shrink = requestedCanvasSize < canvasSize - max(2, canvasSize / 16)
    let canvasNeedsRebuild = !canvasExists || grow || shrink

    if canvasNeedsRebuild {
      guard rebuildCanvasTextures(size: requestedCanvasSize,
                                  preserveContent: canvasExists) else { return false }
    }

    let displayNeedsRebuild = displayTextures.count != 2
        || displayWidth != lastDisplayWidth
        || displayHeight != lastDisplayHeight

    if displayNeedsRebuild {
      guard rebuildDisplayTexture(width: displayWidth, height: displayHeight) else { return false }

      pigmentFullRefreshFrames = max(pigmentFullRefreshFrames, 2)
    }

    if canvasNeedsRebuild || displayNeedsRebuild {
      residencySet.commit()
    }

    return true
  }

  private struct WarmUpTextures {
    let color: [MTLTexture]
    let heightWet: [MTLTexture]
    let velocity: MTLTexture
    let display: MTLTexture
    let dryColor: [MTLTexture]
    let substrate: [MTLTexture]
  }

  private func makeWarmUpTextures() -> WarmUpTextures? {
    let colDesc = Self.makeCanvasDescriptor(width: 64, height: 64)
    let hwDesc = Self.makeHeightWetDescriptor(width: 64, height: 64)
    let velDesc = Self.makeVelocityDescriptor(width: 64, height: 64)
    let dispDesc = Self.makeDisplayDescriptor(width: 64, height: 64)
    let dryDesc = Self.makeDryColorDescriptor(width: 64, height: 64)

    guard let cA = device.makeTexture(descriptor: colDesc),
          let cB = device.makeTexture(descriptor: colDesc),
          let hwA = device.makeTexture(descriptor: hwDesc),
          let hwB = device.makeTexture(descriptor: hwDesc),
          let vel = device.makeTexture(descriptor: velDesc),
          let disp = device.makeTexture(descriptor: dispDesc),
          let dcA = device.makeTexture(descriptor: dryDesc),
          let dcB = device.makeTexture(descriptor: dryDesc),
          let sA = device.makeTexture(descriptor: dryDesc),
          let sB = device.makeTexture(descriptor: dryDesc) else { return nil }

    return WarmUpTextures(color: [cA, cB],
                          heightWet: [hwA, hwB],
                          velocity: vel,
                          display: disp,
                          dryColor: [dcA, dcB],
                          substrate: [sA, sB])
  }

  private func encodeWarmUpPasses(encoder: any MTL4ComputeCommandEncoder,
                                  tex: WarmUpTextures, selfTestResults: MTLBuffer?,
                                  paletteMixResults: MTLBuffer?) {
    let cc = Self.canvasColor
    let params = AbExParams(
      canvas: SIMD4(cc.x, cc.y, cc.z, 0),
      config: SIMD4(0, 1, 0, 10),
      camera: SIMD4(0, 0, 1, 0),
      atmosphere: .zero)

    renderPaint(encoder: encoder,
                colorIn: tex.color[0], colorOut: tex.color[1],
                hwIn: tex.heightWet[0], hwOut: tex.heightWet[1],
                velocityIn: tex.velocity,
                dryColorIn: tex.dryColor[0], dryColorOut: tex.dryColor[1],
                substrateIn: tex.substrate[0], substrateOut: tex.substrate[1],
                params: params, strokes: [],
                tileMap: TileMap.empty,
                region: CanvasRegion(x: 0, y: 0, width: 64, height: 64))
    encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
    renderCompose(encoder: encoder,
                  color: tex.color[1], heightWet: tex.heightWet[1],
                  dryColor: tex.dryColor[1],
                  substrate: tex.substrate[1],
                  output: tex.display, params: params)
    if let b = selfTestResults {
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      encodeMixboxSelfTest(encoder: encoder, results: b)
    }
    if let b = paletteMixResults {
      encoder.barrier(afterEncoderStages: .dispatch, beforeEncoderStages: .dispatch)
      encodePaletteMixes(encoder: encoder, results: b)
    }
  }

  func warmUpGPU() {
    guard let tex = makeWarmUpTextures() else { return }
    let dummies = tex.color + tex.heightWet + [tex.velocity, tex.display]
                + tex.dryColor + tex.substrate
    for t in dummies { residencySet.addAllocation(t) }
    let selfTestResults = makeMixboxSelfTestBuffer()
    if let b = selfTestResults { residencySet.addAllocation(b) }
    let paletteMixResults = makePaletteMixBuffer()
    if let b = paletteMixResults { residencySet.addAllocation(b) }
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

    encodeWarmUpPasses(encoder: encoder, tex: tex, selfTestResults: selfTestResults,
                       paletteMixResults: paletteMixResults)

    encoder.endEncoding()
    commandBuffer.endCommandBuffer()
    commandQueue.commit([commandBuffer])
    commandQueue.signalEvent(sharedEvent, value: warmupFrame)
    frameNumber = warmupFrame

    let completed = sharedEvent.wait(untilSignaledValue: warmupFrame, timeoutMS: 1000)
    if let b = selfTestResults {
      if completed { reportMixboxSelfTest(results: b) }
      residencySet.removeAllocation(b)
    }
    if let b = paletteMixResults {
      if completed { readPaletteMixes(results: b) }
      residencySet.removeAllocation(b)
    }
    for t in dummies { residencySet.removeAllocation(t) }
    residencySet.commit()
  }
}

#endif
