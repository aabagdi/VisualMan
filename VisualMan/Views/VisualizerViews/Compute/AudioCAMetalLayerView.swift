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
import Dependencies
import os

private nonisolated let blitLogger = Logger(subsystem: "com.VisualMan", category: "AudioMetalView")

struct AudioCAMetalLayerView<R: MetalVisualizerRenderer>: UIViewRepresentable {
  let renderer: R
  var config: MetalViewConfig = MetalViewConfig()

  func makeUIView(context: Context) -> CAMetalHostView {
    let makeState = pointsOfInterest.beginInterval("Make Metal View", id: pointsOfInterest.makeSignpostID(),
                                                   "\(String(describing: R.self), privacy: .public)")
    defer { pointsOfInterest.endInterval("Make Metal View", makeState) }
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
    view.accessibilityIgnoresInvertColors = true

    context.coordinator.clearColor = config.clearColor
    context.coordinator.maxFPS = config.maxFramesPerSecond
    context.coordinator.attach(view: view)
    return view
  }

  func updateUIView(_ uiView: CAMetalHostView, context: Context) {
    context.coordinator.clearColor = config.clearColor
    context.coordinator.maxFPS = config.maxFramesPerSecond
  }

  static func dismantleUIView(_ uiView: CAMetalHostView, coordinator: Coordinator) {
    let dismantleState = pointsOfInterest.beginInterval("Dismantle Metal View", id: pointsOfInterest.makeSignpostID(),
                                                        "\(String(describing: R.self), privacy: .public)")
    defer { pointsOfInterest.endInterval("Dismantle Metal View", dismantleState) }
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
    @Dependency(AudioEngineManager.self) private var audioManager
    var clearColor: MTLClearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
    private var lastFrameTime: CFTimeInterval = 0
    let config: MetalViewConfig
    private var tracksDisplayHeadroom = false
    private var blitPipeline: (any MTLRenderPipelineState)?
    let blitArgumentTables: [any MTL4ArgumentTable]
    let presentCommandBuffer: (any MTL4CommandBuffer)?
    let presentAllocators: [any MTL4CommandAllocator]
    let presentEvent: MTLSharedEvent?
    var presentCount: UInt64 = 0
    var firstFrameState: OSSignpostIntervalState?

    private var thermalObserver: (any NSObjectProtocol)?
    private var lifecycle: AppLifecycleObserver?
    private var currentThermalState: ProcessInfo.ThermalState = .nominal
    private var drawableScaleFactor: CGFloat = 1.0
    private weak var hostView: CAMetalHostView?
    private var displayLink: CADisplayLink?
    private var isInBackground = false
    private var isInWindow = false
    private var targetFPS: Int = 120
    let pacer = FramePacer()
    private var pacedFPS: Int = 120
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
      if config.pacesFrameRate { pacedFPS = FramePacer.startRate }

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

    isolated deinit {
      if let observer = thermalObserver {
        NotificationCenter.default.removeObserver(observer)
      }
    }

    private func setBackgrounded(_ background: Bool) {
      isInBackground = background
      displayLink?.isPaused = background || !isInWindow
      if !background {
        pacer.reset()
        renderer.recoverFromStalledGPU()
        recoverFromStalledPresents()
      }
    }

    func attach(view: CAMetalHostView) {
      firstFrameState = pointsOfInterest.beginInterval("Time to First Frame", id: pointsOfInterest.makeSignpostID(),
                                                       "\(String(describing: R.self), privacy: .public)")
      self.hostView = view
      renderer.commandQueue.addResidencySet(view.metalLayer.residencySet)
      view.onWindowAttach = { [weak self] in
        self?.windowAttached()
      }
      view.onWindowDetach = { [weak self] in
        self?.windowDetached()
      }
      if view.window != nil {
        windowAttached()
      }
    }

    private func windowAttached() {
      isInWindow = true
      configureDrawable()
      startDisplayLinkIfNeeded()
      displayLink?.isPaused = isInBackground
    }

    private func windowDetached() {
      isInWindow = false
      displayLink?.isPaused = true
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
      if let firstFrameState {
        pointsOfInterest.endInterval("Time to First Frame", firstFrameState, "Detached before first frame")
        self.firstFrameState = nil
      }
      hostView?.onWindowAttach = nil
      hostView?.onWindowDetach = nil
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
      let screen = hostView?.window?.windowScene?.screen
      let link = screen?.displayLink(withTarget: self, selector: #selector(onDisplayLink))
        ?? CADisplayLink(target: self, selector: #selector(onDisplayLink))
      link.preferredFrameRateRange = makeFrameRateRange()
      link.add(to: .main, forMode: .common)
      self.displayLink = link
    }

    private func makeFrameRateRange() -> CAFrameRateRange {
      let preferred = Float(min(targetFPS, maxFPS, pacedFPS))
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
      guard let view = hostView, !isInBackground, !pacer.takeFrameSkip() else { return }

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

      updatePacing()

      let audioLevels = audioManager.audioLevels
      let intermediateTex = renderer.encodeFrame(
        bass: audioLevels.bassLevel,
        mid: audioLevels.midLevel,
        high: audioLevels.highLevel,
        drawableWidth: scaledWidth,
        drawableHeight: scaledHeight
      )

      let submitted = CACurrentMediaTime()
      commitOrTrackSkippedFrame(encoded: intermediateTex != nil)

      guard intermediateTex != nil || !hasEverPresented,
            let drawable = pacer.acquireDrawable(skipsAfterWait: config.pacesFrameRate && hasEverPresented,
                                                 view.metalLayer.nextDrawable) else { return }

      presentFrame(pipeline: blitPipeline,
                   intermediateTex: intermediateTex,
                   drawable: drawable,
                   submitted: submitted)
      hasEverPresented = true
    }
  }
}

extension AudioCAMetalLayerView.Coordinator {
  private func commitOrTrackSkippedFrame(encoded: Bool) {
    if encoded {
      renderer.commitCompute()
      consecutiveSkippedFrames = 0
      return
    }
    consecutiveSkippedFrames += 1
    if consecutiveSkippedFrames >= stalledGPUFrameThreshold {
      consecutiveSkippedFrames = 0
      renderer.recoverFromStalledGPU()
      recoverFromStalledPresents()
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

  private func updatePacing() {
    guard config.pacesFrameRate, let link = displayLink, let cost = pacer.takeFrameCost() else { return }
    let linkPeriod = link.targetTimestamp - link.timestamp
    let requestedPeriod = 1 / Double(min(targetFPS, maxFPS, pacedFPS))
    let rate = FramePacer.rate(current: pacedFPS, cost: cost, displayPeriod: max(linkPeriod, requestedPeriod))
    guard rate != pacedFPS else { return }
    let costMS = cost * 1000
    let periodMS = linkPeriod * 1000
    blitLogger.info("""
      Display rate \(self.pacedFPS) -> \(rate) Hz, frames cost \(costMS, format: .fixed(precision: 2)) ms, \
      link period \(periodMS, format: .fixed(precision: 2)) ms
      """)
    pacedFPS = rate
    link.preferredFrameRateRange = makeFrameRateRange()
    pacer.reset()
  }
}

#endif
