//
//  AudioCAMetalLayerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

#if !targetEnvironment(simulator)
import SwiftUI
import MetalKit
import QuartzCore
import os

private nonisolated let blitLogger = Logger(subsystem: "com.VisualMan", category: "AudioMetalView")

struct AudioCAMetalLayerView<R: MetalVisualizerRenderer>: UIViewRepresentable {
  let renderer: R
  let audioLevels: [1024 of Float]
  var config: MetalViewConfig = MetalViewConfig()

  func makeUIView(context: Context) -> CAMetalHostView {
    let view = CAMetalHostView()
    let layer = view.metalLayer
    layer.device = renderer.device
    layer.pixelFormat = config.pixelFormat
    layer.framebufferOnly = true
    layer.maximumDrawableCount = 3
    layer.isOpaque = true
    layer.backgroundColor = CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1)
    view.backgroundColor = config.backgroundColor ?? .black
    view.isOpaque = true

    context.coordinator.clearColor = config.clearColor
    context.coordinator.maxFPS = config.maxFramesPerSecond
    context.coordinator.attach(view: view)
    return view
  }

  func updateUIView(_ uiView: CAMetalHostView, context: Context) {
    context.coordinator.audioLevels = audioLevels
    context.coordinator.clearColor = config.clearColor
    context.coordinator.maxFPS = config.maxFramesPerSecond
  }

  static func dismantleUIView(_ uiView: CAMetalHostView, coordinator: Coordinator) {
    coordinator.detach()
    let renderer = coordinator.renderer
    renderer.sharedEvent.wait(untilSignaledValue: renderer.frameNumber, timeoutMS: 100)
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(renderer: renderer, config: config)
  }

  @MainActor
  final class Coordinator: NSObject {
    let renderer: R
    var audioLevels: [1024 of Float] = .init(repeating: 0.0)
    var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    private var lastFrameTime: CFTimeInterval = 0
    private let config: MetalViewConfig
    private var tracksDisplayHeadroom = false
    private var blitPipeline: (any MTLRenderPipelineState)?
    private let blitArgumentTables: [any MTL4ArgumentTable]
    private let presentCommandBuffer: (any MTL4CommandBuffer)?
    private let presentAllocators: [any MTL4CommandAllocator]
    private let presentEvent: MTLSharedEvent?
    private var presentCount: UInt64 = 0

    nonisolated(unsafe) private var thermalObserver: (any NSObjectProtocol)?
    private var lifecycle: AppLifecycleObserver?
    private var currentThermalState: ProcessInfo.ThermalState = .nominal
    private var drawableScaleFactor: CGFloat = 1.0
    private weak var hostView: CAMetalHostView?
    private var displayLink: CADisplayLink?
    private var isInBackground = false
    private var targetFPS: Int = 120
    var maxFPS: Int = 120 {
      didSet {
        guard maxFPS != oldValue else { return }
        displayLink?.preferredFrameRateRange = makeFrameRateRange()
      }
    }
    private var framesRendered: Int = 0
    private var gpuRampedUp = false
    private let rampUpFrameThreshold = 30
    private var hasEverPresented = false
    private var consecutiveSkippedFrames = 0
    private let stalledGPUFrameThreshold = 120

    init(renderer: R, config: MetalViewConfig) {
      self.renderer = renderer
      self.config = config

      let device = renderer.device
      let blit = Self.makeBlitResources(device: device, pixelFormat: config.pixelFormat)
      self.blitPipeline = blit.pipeline
      self.blitArgumentTables = blit.tables
      self.presentAllocators = Self.makePresentAllocators(device: device)
      self.presentCommandBuffer = device.makeCommandBuffer()
      self.presentEvent = device.makeSharedEvent()

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
      lifecycle = AppLifecycleObserver(
        onBackground: { [weak self] in self?.setBackgrounded(true) },
        onForeground: { [weak self] in self?.setBackgrounded(false) })
    }

    deinit {
      if let observer = thermalObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }

    private func setBackgrounded(_ background: Bool) {
      isInBackground = background
      displayLink?.isPaused = background
      if !background {
        renderer.recoverFromStalledGPU()
        recoverFromStalledPresents()
      }
    }

    func attach(view: CAMetalHostView) {
      self.hostView = view
      renderer.commandQueue.addResidencySet(view.metalLayer.residencySet)
      view.onWindowAttach = { [weak self] in
        self?.configureDrawable()
        self?.startDisplayLinkIfNeeded()
      }
      if view.window != nil {
        configureDrawable()
        startDisplayLinkIfNeeded()
      }
    }

    private func configureDrawable() {
      guard let layer = hostView?.metalLayer else { return }
      let screen = hostView?.window?.windowScene?.screen
      let extended = config.wantsExtendedDynamicRange && (screen.map { $0.potentialEDRHeadroom > 1 } ?? true)
      let fallsBack = config.wantsExtendedDynamicRange && !extended
      let pixelFormat = fallsBack ? config.standardRangePixelFormat : config.pixelFormat
      if pixelFormat != layer.pixelFormat {
        blitPipeline = Self.makeBlitResources(device: renderer.device, pixelFormat: pixelFormat).pipeline
      }
      layer.pixelFormat = pixelFormat
      layer.colorspace = fallsBack ? config.standardRangeColorSpace : config.colorSpace
      layer.wantsExtendedDynamicRangeContent = extended
      tracksDisplayHeadroom = extended
      if !extended {
        renderer.setDisplayHeadroom(1)
      }
    }

    func detach() {
      hostView?.onWindowAttach = nil
      if let hostView {
        presentEvent?.wait(untilSignaledValue: presentCount, timeoutMS: 100)
        renderer.commandQueue.removeResidencySet(hostView.metalLayer.residencySet)
      }
      displayLink?.invalidate()
      displayLink = nil
      hostView = nil
    }

    private func startDisplayLinkIfNeeded() {
      guard displayLink == nil else { return }
      let link = CADisplayLink(target: self, selector: #selector(onDisplayLink))
      link.preferredFrameRateRange = makeFrameRateRange()
      link.add(to: .main, forMode: .common)
      self.displayLink = link
    }

    private func makeFrameRateRange() -> CAFrameRateRange {
      let preferred = Float(min(targetFPS, maxFPS))
      
      if preferred >= 120 {
        return CAFrameRateRange(minimum: 60, maximum: preferred, preferred: preferred)
      }
      return CAFrameRateRange(minimum: preferred, maximum: preferred, preferred: preferred)
    }

    @objc private func onDisplayLink() {
      autoreleasepool {
        drawFrame()
      }
    }

    private func drawFrame() {
      guard let view = hostView, !isInBackground else { return }

      framesRendered += 1
      if !gpuRampedUp && framesRendered >= rampUpFrameThreshold {
        gpuRampedUp = true
      }

      let drawableSize = view.metalLayer.drawableSize
      let scaledWidth = Int((drawableSize.width * drawableScaleFactor).rounded())
      let scaledHeight = Int((drawableSize.height * drawableScaleFactor).rounded())
      guard scaledWidth > 0, scaledHeight > 0 else { return }

      let now = CACurrentMediaTime()
      if lastFrameTime > 0, now - lastFrameTime > 0.1 {
        renderer.prepareForResume()
      }
      lastFrameTime = now

      guard let blitPipeline,
            !blitArgumentTables.isEmpty,
            !presentAllocators.isEmpty,
            presentCommandBuffer != nil,
            presentEvent != nil else { return }

      if tracksDisplayHeadroom, let screen = view.window?.windowScene?.screen {
        renderer.setDisplayHeadroom(Float(screen.currentEDRHeadroom))
      }

      let intermediateTex = renderer.encodeFrame(
        bass: audioLevels.bassLevel,
        mid: audioLevels.midLevel,
        high: audioLevels.highLevel,
        drawableWidth: scaledWidth,
        drawableHeight: scaledHeight
      )

      if intermediateTex != nil {
        renderer.commitCompute()
        consecutiveSkippedFrames = 0
      } else {
        consecutiveSkippedFrames += 1
        if consecutiveSkippedFrames >= stalledGPUFrameThreshold {
          consecutiveSkippedFrames = 0
          renderer.recoverFromStalledGPU()
          recoverFromStalledPresents()
        }
      }

      guard intermediateTex != nil || !hasEverPresented,
            let drawable = view.metalLayer.nextDrawable() else { return }

      presentFrame(pipeline: blitPipeline,
                   intermediateTex: intermediateTex,
                   drawable: drawable)
      hasEverPresented = true
    }

  }
}

extension AudioCAMetalLayerView.Coordinator {
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
      targetFPS = 120
      drawableScaleFactor = 0.9
    case .serious:
      targetFPS = 60
      drawableScaleFactor = 0.7
    case .critical:
      targetFPS = 60
      drawableScaleFactor = 0.55
    @unknown default:
      targetFPS = 60
      drawableScaleFactor = 1.0
    }
    displayLink?.preferredFrameRateRange = makeFrameRateRange()
  }
}

extension AudioCAMetalLayerView.Coordinator {
  private static func makeBlitResources(device: MTLDevice, pixelFormat: MTLPixelFormat)
  -> (pipeline: (any MTLRenderPipelineState)?, tables: [any MTL4ArgumentTable]) {
    guard let library = device.makeDefaultLibrary() else {
      blitLogger.error("Failed to create default Metal library for blit pipeline")
      return (nil, [])
    }
    do {
      let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

      let vertexDesc = MTL4LibraryFunctionDescriptor()
      vertexDesc.name = "blitVertex"
      vertexDesc.library = library

      let fragmentDesc = MTL4LibraryFunctionDescriptor()
      fragmentDesc.name = "blitFragment"
      fragmentDesc.library = library

      let pipelineDesc = MTL4RenderPipelineDescriptor()
      pipelineDesc.vertexFunctionDescriptor = vertexDesc
      pipelineDesc.fragmentFunctionDescriptor = fragmentDesc
      pipelineDesc.colorAttachments[0].pixelFormat = pixelFormat
      let pipeline = try compiler.makeRenderPipelineState(descriptor: pipelineDesc)

      let tableDesc = MTL4ArgumentTableDescriptor()
      tableDesc.maxTextureBindCount = 1
      var tables = [any MTL4ArgumentTable]()
      for _ in 0..<R.maxFramesInFlight {
        tables.append(try device.makeArgumentTable(descriptor: tableDesc))
      }
      return (pipeline, tables)
    } catch {
      blitLogger.error("Failed to create blit pipeline: \(error.localizedDescription)")
      return (nil, [])
    }
  }

  private static func makePresentAllocators(device: MTLDevice) -> [any MTL4CommandAllocator] {
    var allocators = [any MTL4CommandAllocator]()
    for _ in 0..<R.maxFramesInFlight {
      guard let allocator = device.makeCommandAllocator() else {
        blitLogger.error("Failed to create present command allocators")
        return []
      }
      allocators.append(allocator)
    }
    return allocators
  }

  private func recoverFromStalledPresents() {
    guard let presentEvent, presentEvent.signaledValue < presentCount else { return }
    presentEvent.wait(untilSignaledValue: presentCount, timeoutMS: 250)
    if presentEvent.signaledValue < presentCount {
      presentEvent.signaledValue = presentCount
    }
  }

  private func presentFrame(pipeline: any MTLRenderPipelineState,
                            intermediateTex: MTLTexture?,
                            drawable: CAMetalDrawable) {
    guard let presentCommandBuffer, let presentEvent else { return }
    let queue = renderer.commandQueue
    let inFlight = R.maxFramesInFlight

    let nextPresent = presentCount + 1
    if nextPresent > inFlight {
      let waitValue = nextPresent - inFlight
      if presentEvent.signaledValue < waitValue {
        presentEvent.wait(untilSignaledValue: waitValue, timeoutMS: 16)
        guard presentEvent.signaledValue >= waitValue else { return }
      }
    }
    presentCount = nextPresent
    let slot = Int(presentCount % inFlight)
    let allocator = presentAllocators[slot]
    allocator.reset()

    let renderPassDesc = MTL4RenderPassDescriptor()
    renderPassDesc.colorAttachments[0].texture = drawable.texture
    renderPassDesc.colorAttachments[0].loadAction = .clear
    renderPassDesc.colorAttachments[0].storeAction = .store
    renderPassDesc.colorAttachments[0].clearColor = clearColor

    presentCommandBuffer.beginCommandBuffer(allocator: allocator)
    if let encoder = presentCommandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) {
      if let intermediateTex {
        encoder.barrier(afterQueueStages: .dispatch, beforeStages: .fragment)
        encoder.setRenderPipelineState(pipeline)
        let table = blitArgumentTables[slot]
        table.setTexture(intermediateTex.gpuResourceID, index: 0)
        encoder.setArgumentTable(table, stages: .fragment)
        encoder.drawPrimitives(primitiveType: .triangle, vertexStart: 0, vertexCount: 3)
      }
      encoder.endEncoding()
    }
    presentCommandBuffer.endCommandBuffer()

    queue.waitForDrawable(drawable)
    queue.commit([presentCommandBuffer])
    queue.signalDrawable(drawable)
    queue.signalEvent(presentEvent, value: presentCount)
    drawable.present()
  }
}

#endif
