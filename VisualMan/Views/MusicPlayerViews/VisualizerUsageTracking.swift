//
//  VisualizerUsageTracking.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/25/26.
//

import SwiftUI
import Dependencies

struct VisualizerUsageTracking: ViewModifier {
  let visualizer: VMVisualizer

  @Environment(\.scenePhase) private var scenePhase
  @Dependency(VisualizerUsageManager.self) private var usageManager
  @Dependency(AudioEngineManager.self) private var audioManager
  @Dependency(ExternalDisplayManager.self) private var externalDisplay
  @Dependency(\.continuousClock) private var clock

  private struct Session: Equatable {
    let visualizer: VMVisualizer
    let isOnScreen: Bool
  }

  func body(content: Content) -> some View {
    let session = Session(
      visualizer: visualizer,
      isOnScreen: scenePhase == .active && audioManager.isPlaying && !externalDisplay.isConnected
    )
    return content
      .task(id: session) { await trackTimeOnScreen(session) }
  }

  private func trackTimeOnScreen(_ session: Session) async {
    guard session.isOnScreen else { return }
    var isCancelled = false
    while !isCancelled {
      let elapsed = await clock.measure {
        isCancelled = (try? await clock.sleep(for: .seconds(5))) == nil
      }
      usageManager.recordTimeOnScreen(session.visualizer, duration: elapsed)
    }
  }
}
