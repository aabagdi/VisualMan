//
//  AppLifecycleObserver.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/1/26.
//

import UIKit

@MainActor
final class AppLifecycleObserver {
  nonisolated(unsafe) private var tokens: [any NSObjectProtocol] = []

  init(onBackground: @escaping @MainActor () -> Void,
       onForeground: @escaping @MainActor () -> Void) {
    let center = NotificationCenter.default
    tokens = [
      center.addObserver(forName: UIApplication.didEnterBackgroundNotification,
                         object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { onBackground() }
      },
      center.addObserver(forName: UIApplication.willEnterForegroundNotification,
                         object: nil, queue: .main) { _ in
        MainActor.assumeIsolated { onForeground() }
      },
    ]
  }

  deinit {
    tokens.forEach { NotificationCenter.default.removeObserver($0) }
  }
}
