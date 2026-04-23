//
//  AudioMetalView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

import SwiftUI
import MetalKit
import QuartzCore
import os

struct MetalViewConfig {
  var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
  var backgroundColor: UIColor?
}

struct AudioMetalView<R: MetalVisualizerRenderer>: UIViewRepresentable {
  let renderer: R
  let audioLevels: [1024 of Float]
  var config: MetalViewConfig = MetalViewConfig()

  func makeUIView(context: Context) -> MTKView {
    let mtkView = MTKView()
    mtkView.device = renderer.device
    mtkView.delegate = context.coordinator
    mtkView.preferredFramesPerSecond = 120
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.framebufferOnly = false
    mtkView.isPaused = false
    mtkView.enableSetNeedsDisplay = false
    mtkView.clearColor = config.clearColor
    mtkView.backgroundColor = config.backgroundColor ?? .black

    if let metalLayer = mtkView.layer as? CAMetalLayer {
      metalLayer.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
      renderer.commandQueue.addResidencySet(metalLayer.residencySet)
    }

    return mtkView
  }

  func updateUIView(_ uiView: MTKView, context: Context) {
    context.coordinator.audioLevels = audioLevels
  }

  static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
    let renderer = coordinator.renderer
    renderer.sharedEvent.wait(untilSignaledValue: renderer.frameNumber, timeoutMS: 100)
    if let metalLayer = uiView.layer as? CAMetalLayer {
      renderer.commandQueue.removeResidencySet(metalLayer.residencySet)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(renderer: renderer)
  }

  @MainActor
  class Coordinator: NSObject, MTKViewDelegate {
    let renderer: R
    var audioLevels: [1024 of Float] = .init(repeating: 0.0)
    private var lastFrameTime: CFTimeInterval = 0

    private let blitPipeline: MTLRenderPipelineState?
    private let blitArgumentTables: [any MTL4ArgumentTable]

    nonisolated(unsafe) private var thermalObserver: (any NSObjectProtocol)?
    private var currentThermalState: ProcessInfo.ThermalState = .nominal
    private var drawableScaleFactor: CGFloat = 1.0
    private var nativeDrawableSize: CGSize = .zero
    private weak var mtkView: MTKView?
    private var targetFPS: Int = 120
    private var isApplyingScale = false
    private var framesRendered: Int = 0
    private var gpuRampedUp = false
    private let rampUpFrameThreshold = 30
    private var hasEverPresented = false

    init(renderer: R) {
      self.renderer = renderer

      let blitLogger = Logger(subsystem: "com.VisualMan", category: "AudioMetalView")
      var pipeline: MTLRenderPipelineState?
      var tables = [any MTL4ArgumentTable]()
      do {
        let compiler = try renderer.device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        guard let library = renderer.device.makeDefaultLibrary() else {
          blitLogger.error("Failed to create default Metal library for blit pipeline")
          self.blitPipeline = nil
          self.blitArgumentTables = []
          super.init()
          return
        }

        let vertexDesc = MTL4LibraryFunctionDescriptor()
        vertexDesc.name = "blitVertex"
        vertexDesc.library = library

        let fragmentDesc = MTL4LibraryFunctionDescriptor()
        fragmentDesc.name = "blitFragment"
        fragmentDesc.library = library

        let pipelineDesc = MTL4RenderPipelineDescriptor()
        pipelineDesc.vertexFunctionDescriptor = vertexDesc
        pipelineDesc.fragmentFunctionDescriptor = fragmentDesc
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipeline = try compiler.makeRenderPipelineState(descriptor: pipelineDesc)

        let tableDesc = MTL4ArgumentTableDescriptor()
        tableDesc.maxTextureBindCount = 1
        for _ in 0..<R.maxFramesInFlight {
          tables.append(try renderer.device.makeArgumentTable(descriptor: tableDesc))
        }
      } catch {
        blitLogger.error("Failed to create blit pipeline: \(error.localizedDescription)")
      }
      self.blitPipeline = pipeline
      self.blitArgumentTables = tables

      super.init()
      currentThermalState = ProcessInfo.processInfo.thermalState
      applyThermalPolicy()
      thermalObserver = NotificationCenter.default.addObserver(
        forName: ProcessInfo.thermalStateDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          self?.thermalStateChanged()
        }
      }
    }

    deinit {
      if let observer = thermalObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }

    private func thermalStateChanged() {
      let newState = ProcessInfo.processInfo.thermalState
      guard newState != currentThermalState else { return }
      currentThermalState = newState
      applyThermalPolicy()
    }

    private func applyThermalPolicy() {
      switch currentThermalState {
      case .nominal:
        targetFPS = 120
        drawableScaleFactor = 1.0
      case .fair:
        targetFPS = 60
        drawableScaleFactor = 1.0
      case .serious:
        targetFPS = 60
        drawableScaleFactor = 0.75
      case .critical:
        targetFPS = 30
        drawableScaleFactor = 0.5
      @unknown default:
        targetFPS = 60
        drawableScaleFactor = 1.0
      }
      if let view = mtkView {
        applyDrawableScale(to: view)
      }
    }

    private func applyDrawableScale(to view: MTKView) {
      view.preferredFramesPerSecond = targetFPS
      guard nativeDrawableSize != .zero else { return }
      let scaledSize = CGSize(
        width: nativeDrawableSize.width * drawableScaleFactor,
        height: nativeDrawableSize.height * drawableScaleFactor
      )
      if view.drawableSize != scaledSize {
        isApplyingScale = true
        view.drawableSize = scaledSize
        isApplyingScale = false
      }
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
      guard !isApplyingScale else { return }
      mtkView = view
      nativeDrawableSize = size
      applyDrawableScale(to: view)
    }

    func draw(in view: MTKView) {
      autoreleasepool {
        drawFrame(in: view)
      }
    }

    private func drawFrame(in view: MTKView) {
      if nativeDrawableSize == .zero, let metalLayer = view.layer as? CAMetalLayer {
        nativeDrawableSize = metalLayer.drawableSize
        mtkView = view
        applyDrawableScale(to: view)
      }

      framesRendered += 1
      if !gpuRampedUp && framesRendered >= rampUpFrameThreshold {
        gpuRampedUp = true
        applyDrawableScale(to: view)
      }

      let drawableSize = view.drawableSize
      guard drawableSize.width > 0, drawableSize.height > 0 else { return }

      let now = CACurrentMediaTime()
      if lastFrameTime > 0, now - lastFrameTime > 0.1 {
        renderer.prepareForResume()
      }
      lastFrameTime = now

      let blitPipeline = blitPipeline
      guard let blitPipeline, !blitArgumentTables.isEmpty else { return }

      let intermediateTex = renderer.encodeFrame(
        bass: audioLevels.bassLevel,
        mid: audioLevels.midLevel,
        high: audioLevels.highLevel,
        drawableWidth: Int(drawableSize.width),
        drawableHeight: Int(drawableSize.height)
      )

      guard let renderPassDesc = view.currentMTL4RenderPassDescriptor,
            let drawable = view.currentDrawable else {
        if intermediateTex != nil {
          commitWithoutDrawable()
        }
        return
      }
      renderPassDesc.colorAttachments[0].loadAction = .clear
      renderPassDesc.colorAttachments[0].storeAction = .store

      if let intermediateTex {
        guard let renderEncoder = renderer.commandBuffer.makeRenderCommandEncoder(
                descriptor: renderPassDesc) else {
          commitWithoutDrawable()
          return
        }
        encodeBlit(renderEncoder, pipeline: blitPipeline, texture: intermediateTex)
        renderer.commitFrame(drawable: drawable)
        hasEverPresented = true
      } else if !hasEverPresented {
        presentClearedDrawable(renderPassDesc: renderPassDesc, drawable: drawable)
        hasEverPresented = true
      }
    }

    private func presentClearedDrawable(renderPassDesc: MTL4RenderPassDescriptor,
                                        drawable: CAMetalDrawable) {
      guard let allocator = renderer.device.makeCommandAllocator(),
            let cmdBuf = renderer.device.makeCommandBuffer() else { return }
      cmdBuf.beginCommandBuffer(allocator: allocator)
      if let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderPassDesc) {
        encoder.endEncoding()
      }
      cmdBuf.endCommandBuffer()
      renderer.commandQueue.commit([cmdBuf])
      renderer.commandQueue.waitForDrawable(drawable)
      renderer.commandQueue.signalDrawable(drawable)
      drawable.present()
    }

    private func commitWithoutDrawable() {
      renderer.commandBuffer.endCommandBuffer()
      renderer.commandQueue.commit([renderer.commandBuffer])
      renderer.commandQueue.signalEvent(renderer.sharedEvent, value: renderer.frameNumber)
    }

    private func encodeBlit(_ encoder: MTL4RenderCommandEncoder,
                            pipeline: MTLRenderPipelineState,
                            texture: MTLTexture) {
      encoder.barrier(afterQueueStages: .dispatch, beforeStages: .fragment)
      encoder.setRenderPipelineState(pipeline)
      let blitTable = blitArgumentTables[Int(renderer.frameNumber % R.maxFramesInFlight)]
      blitTable.setTexture(texture.gpuResourceID, index: 0)
      encoder.setArgumentTable(blitTable, stages: .fragment)
      encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
      encoder.endEncoding()
    }
  }
}
