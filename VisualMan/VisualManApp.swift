//
//  VisualManApp.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 7/7/25.
//

import SwiftUI

@main
struct VisualManApp: App {
  @StateObject var musicLibraryManager = MusicLibraryAccessManager()
  
  var body: some Scene {
    WindowGroup {
      HomeScreenView()
        .environmentObject(musicLibraryManager)
    }
  }
}
