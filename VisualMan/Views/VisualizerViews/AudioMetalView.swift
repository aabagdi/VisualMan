//
//  AudioMetalView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

import SwiftUI
import MetalKit
import QuartzCore

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
    mtkView.preferredFramesPerSecond = 60
    mtkView.colorPixelFormat = .bgra8Unorm
    mtkView.framebufferOnly = false
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
    private var smoothedBass: Float = 0
    private var smoothedMid: Float = 0
    private var smoothedHigh: Float = 0
    private var needsSeedSmoothing = true
    private var lastFrameTime: CFTimeInterval = 0
    
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
      view.preferredFramesPerSecond = gpuRampedUp ? targetFPS : 60
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

      guard let drawable = view.currentDrawable else { return }

      let now = CACurrentMediaTime()
      if lastFrameTime > 0 {
        let delta = Float(now - lastFrameTime)
        renderer.dt = min(delta, 1.0 / 30.0)
      }
      lastFrameTime = now
      
      let bass = audioLevels.bassLevel
      let mid = audioLevels.midLevel
      let high = audioLevels.highLevel

      if needsSeedSmoothing {
        smoothedBass = bass
        smoothedMid = mid
        smoothedHigh = high
        needsSeedSmoothing = false
      } else {
        let bSmooth: Float = bass > smoothedBass ? 0.2 : 0.85
        smoothedBass = smoothedBass * bSmooth + bass * (1.0 - bSmooth)

        let mSmooth: Float = mid > smoothedMid ? 0.25 : 0.8
        smoothedMid = smoothedMid * mSmooth + mid * (1.0 - mSmooth)

        let hSmooth: Float = high > smoothedHigh ? 0.15 : 0.75
        smoothedHigh = smoothedHigh * hSmooth + high * (1.0 - hSmooth)
      }
      
      renderer.update(bass: smoothedBass,
                      mid: smoothedMid,
                      high: smoothedHigh,
                      drawable: drawable)
    }
  }
}
