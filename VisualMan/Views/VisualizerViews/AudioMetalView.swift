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
    mtkView.framebufferOnly = true
    mtkView.isPaused = false
    mtkView.enableSetNeedsDisplay = false
    mtkView.clearColor = config.clearColor
    if let bg = config.backgroundColor {
      mtkView.backgroundColor = bg
    }

    if let metalLayer = mtkView.layer as? CAMetalLayer {
      renderer.commandQueue.addResidencySet(metalLayer.residencySet)
    }

    return mtkView
  }

  func updateUIView(_ uiView: MTKView, context: Context) {
    context.coordinator.audioLevels = audioLevels
  }

  static func dismantleUIView(_ uiView: MTKView, coordinator: Coordinator) {
    if let metalLayer = uiView.layer as? CAMetalLayer {
      coordinator.renderer.commandQueue.removeResidencySet(metalLayer.residencySet)
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
    private let blitArgumentTable: (any MTL4ArgumentTable)?

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

    init(renderer: R) {
      self.renderer = renderer

      let blitLogger = Logger(subsystem: "com.VisualMan", category: "AudioMetalView")
      var pipeline: MTLRenderPipelineState?
      var table: (any MTL4ArgumentTable)?
      do {
        let compiler = try renderer.device.makeCompiler(descriptor: MTL4CompilerDescriptor())
        guard let library = renderer.device.makeDefaultLibrary() else {
          blitLogger.error("Failed to create default Metal library for blit pipeline")
          self.blitPipeline = nil
          self.blitArgumentTable = nil
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
        table = try renderer.device.makeArgumentTable(descriptor: tableDesc)
      } catch {
        blitLogger.error("Failed to create blit pipeline: \(error.localizedDescription)")
      }
      self.blitPipeline = pipeline
      self.blitArgumentTable = table

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

      guard renderer.canRenderThisFrame() else { return }

      let drawableSize = view.drawableSize
      guard drawableSize.width > 0, drawableSize.height > 0 else { return }

      let now = CACurrentMediaTime()
      if lastFrameTime > 0 {
        let delta = now - lastFrameTime
        if delta > 0.1 {
          renderer.prepareForResume()
        }
      }
      lastFrameTime = now

      let bass = audioLevels.bassLevel
      let mid = audioLevels.midLevel
      let high = audioLevels.highLevel

      guard let intermediateTex = renderer.encodeFrame(
        bass: bass,
        mid: mid,
        high: high,
        drawableWidth: Int(drawableSize.width),
        drawableHeight: Int(drawableSize.height)
      ) else {
        return
      }

      guard let renderPassDesc = view.currentMTL4RenderPassDescriptor,
            let drawable = view.currentDrawable else { return }
      renderPassDesc.colorAttachments[0].loadAction = .dontCare

      guard let blitPipeline,
            let blitTable = blitArgumentTable,
            let renderEncoder = renderer.commandBuffer.makeRenderCommandEncoder(
              descriptor: renderPassDesc) else {
        return
      }
      renderEncoder.barrier(afterQueueStages: .dispatch, beforeStages: .fragment)
      renderEncoder.setRenderPipelineState(blitPipeline)
      blitTable.setTexture(intermediateTex.gpuResourceID, index: 0)
      renderEncoder.setArgumentTable(blitTable, stages: .fragment)
      renderEncoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
      renderEncoder.endEncoding()

      renderer.commitFrame(drawable: drawable)
    }
  }
}
