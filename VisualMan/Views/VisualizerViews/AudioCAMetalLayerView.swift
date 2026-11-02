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

final class CAMetalHostView: UIView {
  override static var layerClass: AnyClass { CAMetalLayer.self }
  var metalLayer: CAMetalLayer {
    guard let layer = layer as? CAMetalLayer else {
      fatalError("CAMetalHostView.layerClass must be CAMetalLayer")
    }
    return layer
  }

  var onWindowAttach: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    updateDrawableSize()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if let window {
      metalLayer.contentsScale = window.screen.nativeScale
      updateDrawableSize()
      onWindowAttach?()
    }
  }

  private func updateDrawableSize() {
    let scale = metalLayer.contentsScale
    let size = CGSize(width: bounds.width * scale,
                      height: bounds.height * scale)
    guard size.width > 0, size.height > 0 else { return }
    if metalLayer.drawableSize != size {
      metalLayer.drawableSize = size
    }
  }
}

struct AudioCAMetalLayerView<R: MetalVisualizerRenderer>: UIViewRepresentable {
  let renderer: R
  let audioLevels: [1024 of Float]
  var config: MetalViewConfig = MetalViewConfig()

  func makeUIView(context: Context) -> CAMetalHostView {
    let view = CAMetalHostView()
    let layer = view.metalLayer
    layer.device = renderer.device
    layer.pixelFormat = .bgra8Unorm
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
    Coordinator(renderer: renderer)
  }

  @MainActor
  final class Coordinator: NSObject {
    let renderer: R
    var audioLevels: [1024 of Float] = .init(repeating: 0.0)
    var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    private var lastFrameTime: CFTimeInterval = 0
    private let presentQueue: (any MTLCommandQueue)?
    private let blitPipeline: (any MTLRenderPipelineState)?

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

    init(renderer: R) {
      self.renderer = renderer

      let blitLogger = Logger(subsystem: "com.VisualMan", category: "AudioMetalView")
      var pipeline: (any MTLRenderPipelineState)?
      var queue: (any MTLCommandQueue)?
      do {
        guard let library = renderer.device.makeDefaultLibrary() else {
          blitLogger.error("Failed to create default Metal library for blit pipeline")
          self.blitPipeline = nil
          self.presentQueue = nil
          super.init()
          return
        }
        guard let vertexFn = library.makeFunction(name: "blitVertex"),
              let fragmentFn = library.makeFunction(name: "blitFragment") else {
          blitLogger.error("Failed to locate blit shader functions")
          self.blitPipeline = nil
          self.presentQueue = nil
          super.init()
          return
        }

        let pipelineDesc = MTLRenderPipelineDescriptor()
        pipelineDesc.vertexFunction = vertexFn
        pipelineDesc.fragmentFunction = fragmentFn
        pipelineDesc.colorAttachments[0].pixelFormat = .bgra8Unorm

        pipeline = try renderer.device.makeRenderPipelineState(descriptor: pipelineDesc)
        queue = renderer.device.makeCommandQueue()
      } catch {
        blitLogger.error("Failed to create blit pipeline: \(error.localizedDescription)")
      }
      self.blitPipeline = pipeline
      self.presentQueue = queue

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
      }
    }

    func attach(view: CAMetalHostView) {
      self.hostView = view
      view.onWindowAttach = { [weak self] in
        self?.startDisplayLinkIfNeeded()
      }
      if view.window != nil {
        startDisplayLinkIfNeeded()
      }
    }

    func detach() {
      hostView?.onWindowAttach = nil
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
        renderer.recoverFromStalledGPU()
        renderer.prepareForResume()
      }
      lastFrameTime = now

      guard let blitPipeline, let presentQueue else { return }

      let intermediateTex = renderer.encodeFrame(
        bass: audioLevels.bassLevel,
        mid: audioLevels.midLevel,
        high: audioLevels.highLevel,
        drawableWidth: scaledWidth,
        drawableHeight: scaledHeight
      )

      let computeFrameValue: UInt64
      if intermediateTex != nil {
        renderer.commitCompute()
        computeFrameValue = renderer.frameNumber
      } else {
        computeFrameValue = 0
      }

      guard let drawable = view.metalLayer.nextDrawable() else { return }
      let drawableTexture = drawable.texture

      if let intermediateTex {
        presentFrame(presentQueue: presentQueue,
                     pipeline: blitPipeline,
                     intermediateTex: intermediateTex,
                     drawable: drawable,
                     drawableTexture: drawableTexture,
                     waitValue: computeFrameValue)
        hasEverPresented = true
      } else if !hasEverPresented {
        presentClearedDrawable(presentQueue: presentQueue,
                               drawable: drawable,
                               drawableTexture: drawableTexture)
        hasEverPresented = true
      }
    }

    private func presentFrame(presentQueue: any MTLCommandQueue,
                              pipeline: any MTLRenderPipelineState,
                              intermediateTex: MTLTexture,
                              drawable: CAMetalDrawable,
                              drawableTexture: MTLTexture,
                              waitValue: UInt64) {
      let renderPassDesc = MTLRenderPassDescriptor()
      renderPassDesc.colorAttachments[0].texture = drawableTexture
      renderPassDesc.colorAttachments[0].loadAction = .clear
      renderPassDesc.colorAttachments[0].storeAction = .store
      renderPassDesc.colorAttachments[0].clearColor = clearColor

      guard let cmdBuf = presentQueue.makeCommandBuffer() else { return }
      if waitValue > 0 {
        cmdBuf.encodeWaitForEvent(renderer.sharedEvent, value: waitValue)
      }
      guard let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
        cmdBuf.commit()
        return
      }
      encoder.setRenderPipelineState(pipeline)
      encoder.setFragmentTexture(intermediateTex, index: 0)
      encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
      encoder.endEncoding()
      cmdBuf.present(drawable)
      cmdBuf.commit()
    }

    private func presentClearedDrawable(presentQueue: any MTLCommandQueue,
                                        drawable: CAMetalDrawable,
                                        drawableTexture: MTLTexture) {
      let renderPassDesc = MTLRenderPassDescriptor()
      renderPassDesc.colorAttachments[0].texture = drawableTexture
      renderPassDesc.colorAttachments[0].loadAction = .clear
      renderPassDesc.colorAttachments[0].storeAction = .store
      renderPassDesc.colorAttachments[0].clearColor = clearColor

      guard let cmdBuf = presentQueue.makeCommandBuffer(),
            let encoder = cmdBuf.makeRenderCommandEncoder(descriptor: renderPassDesc) else {
        return
      }
      encoder.endEncoding()
      cmdBuf.present(drawable)
      cmdBuf.commit()
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

#endif
