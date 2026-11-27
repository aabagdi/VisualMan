//
//  MetalVisualizerContainerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/22/26.
//

#if !targetEnvironment(simulator)
import SwiftUI
import Metal

struct MetalRendererNoConfiguration: Equatable {}

struct MetalVisualizerContainerView<R: MetalVisualizerRenderer, Configuration: Equatable>: View {
  @Environment(VisualizerRendererCache.self) private var cache
  @State private var renderer: R?
  @State private var rendererFailed = false

  let config: MetalViewConfig
  let configuration: Configuration
  let configure: @MainActor (R, Configuration) -> Void
  let factory: @MainActor (MTLDevice) async -> R?

  init(config: MetalViewConfig,
       configuration: Configuration,
       configure: @escaping @MainActor (R, Configuration) -> Void,
       factory: @escaping @MainActor (MTLDevice) async -> R?) {
    self.config = config
    self.configuration = configuration
    self.configure = configure
    self.factory = factory
  }

  private var resolvedRenderer: R? {
    renderer ?? cache.renderer(R.self)
  }

  var body: some View {
    ZStack {
      Color.black
      if let resolved = resolvedRenderer {
        AudioMetalView(renderer: resolved, config: config)
          .accessibilityHidden(true)
      } else if rendererFailed {
        ContentUnavailableView("Renderer Unavailable",
                               systemImage: "exclamationmark.triangle",
                               description: Text("Metal rendering is not available on this device."))
      } else {
        ProgressView("Loading visualizer")
      }
    }
    .ignoresSafeArea()
    .onAppear { cache.beginUse(R.self) }
    .onDisappear { cache.endUse(R.self) }
    .onChange(of: configuration, initial: true) {
      applyConfiguration()
    }
    .onChange(of: renderer.map(ObjectIdentifier.init)) {
      applyConfiguration()
    }
    .task {
      guard renderer == nil else { return }
      if let cached = cache.renderer(R.self) {
        renderer = cached
      } else {
        renderer = await cache.renderer(R.self) {
          guard let device = cache.getOrCreateDevice() else { return nil }
          return await factory(device)
        }
      }
      if renderer == nil { rendererFailed = true }
    }
  }

  private func applyConfiguration() {
    guard let resolved = resolvedRenderer else { return }
    configure(resolved, configuration)
  }
}

extension MetalVisualizerContainerView where Configuration == MetalRendererNoConfiguration {
  init(config: MetalViewConfig, factory: @escaping @MainActor (MTLDevice) async -> R?) {
    self.init(config: config, configuration: MetalRendererNoConfiguration(), configure: { _, _ in }, factory: factory)
  }
}

#endif
