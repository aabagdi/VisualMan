//
//  VisualizerSnapshot.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

import QuartzCore
import UIKit

@MainActor
enum VisualizerSnapshot {
  static func capture() -> Bool {
    guard let window = UIApplication
      .shared
      .connectedScenes
      .compactMap({ $0 as? UIWindowScene })
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
    else {
      return false
    }

    let renderer = UIGraphicsImageRenderer(bounds: window.bounds)
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    let image = renderer.image { _ in
      window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
    }
    CATransaction.commit()

    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    return true
  }
}
