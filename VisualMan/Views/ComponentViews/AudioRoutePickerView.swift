//
//  AudioRoutePickerView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/20/26.
//

import SwiftUI
import AVKit
import Dependencies

struct AudioRoutePickerView: View {
  var tintColor: UIColor = .label
  var activeTintColor: UIColor = .tintColor

  @Dependency(ExternalDisplayManager.self) private var externalDisplay
  @Dependency(\.continuousClock) private var clock

  @AppStorage("hideScreenMirroringHint") private var hideScreenMirroringHint = false

  @State private var isRoutedExternally = false
  @State private var isRoutedToAirPlay = false
  @State private var airPlaySwitchCount = 0
  @State private var showScreenMirroringHint = false

  var body: some View {
    RoutePickerRepresentable()
      .overlay {
        Image(systemName: "airplay.audio")
          .foregroundStyle(Color(isRoutedExternally ? activeTintColor : tintColor))
          .allowsHitTesting(false)
      }
      .task {
        updateRoute(isInitial: true)
        for await _ in NotificationCenter.default.notifications(named: AVAudioSession.routeChangeNotification) {
          updateRoute(isInitial: false)
        }
      }
      .task(id: airPlaySwitchCount) {
        guard airPlaySwitchCount > 0, !hideScreenMirroringHint else { return }
        do {
          try await clock.sleep(for: .seconds(1.5))
        } catch {
          return
        }
        guard isRoutedToAirPlay, !externalDisplay.isConnected else { return }
        showScreenMirroringHint = true
      }
      .alert("Show the Visualizer on Your TV", isPresented: $showScreenMirroringHint) {
        Button("OK") { }
        Button("Cancel", role: .close) {}
        Button("Don't Show Again") {
          hideScreenMirroringHint = true
        }
      } message: {
        Text("If this AirPlay device is a TV, turn on screen mirroring. VisualMan will then stream the visualizer to the external display.")
      }
  }

  private func updateRoute(isInitial: Bool) {
    let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
    isRoutedExternally = outputs.contains {
      [.airPlay, .bluetoothA2DP, .HDMI, .carAudio].contains($0.portType)
    }
    let airPlay = outputs.contains { $0.portType == .airPlay }
    if airPlay && !isRoutedToAirPlay && !isInitial {
      airPlaySwitchCount += 1
    }
    isRoutedToAirPlay = airPlay
  }
}

private struct RoutePickerRepresentable: UIViewRepresentable {
  func makeUIView(context: Context) -> AVRoutePickerView {
    let picker = AVRoutePickerView()
    picker.prioritizesVideoDevices = true
    picker.backgroundColor = .clear
    picker.tintColor = .clear
    picker.activeTintColor = .clear
    return picker
  }

  func updateUIView(_ uiView: AVRoutePickerView, context: Context) {}
}
