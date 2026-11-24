//
//  SettingsToolbarButton.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import SwiftUI

struct SettingsToolbarButton: ViewModifier {
  @State private var isShowingSettings = false

  func body(content: Content) -> some View {
    content
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) {
          Button("Settings", systemImage: "gearshape") {
            isShowingSettings = true
          }
        }
      }
      .sheet(isPresented: $isShowingSettings) {
        NavigationStack {
          SettingsView()
        }
        .presentationDetents([.medium, .large])
      }
  }
}
