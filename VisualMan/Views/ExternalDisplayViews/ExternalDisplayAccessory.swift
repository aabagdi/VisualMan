//
//  ExternalDisplayAccessory.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/20/26.
//

import SwiftUI
import Dependencies

struct ExternalDisplayAccessory: ViewModifier {
  @Dependency(ExternalDisplayManager.self) private var externalDisplay

  func body(content: Content) -> some View {
    if #available(iOS 27.0, *) {
      content
        .sceneAccessory {
          ExternalNonInteractiveAccessory {
            ExternalDisplayView()
              .onAppear { externalDisplay.sceneConnected() }
              .onDisappear { externalDisplay.sceneDisconnected() }
          }
        }
    } else {
      content
    }
  }
}
