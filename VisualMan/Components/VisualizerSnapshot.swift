//
//  VisualizerSnapshot.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/23/26.
//

import SwiftUI
import UIKit

@MainActor
@Observable
final class VisualizerSnapshotter {
  @ObservationIgnored weak var captureView: UIView?
  @ObservationIgnored var snapshotOverride: (@MainActor () async -> UIImage?)?

  func capture() async -> Bool {
    let image: UIImage?

    if let override = snapshotOverride {
      image = await override()
    } else if let view = captureView, view.bounds.width > 0, view.bounds.height > 0 {
      let format = UIGraphicsImageRendererFormat()
      format.scale = view.window?.windowScene?.screen.scale ?? view.traitCollection.displayScale
      format.opaque = false

      let renderer = UIGraphicsImageRenderer(bounds: view.bounds, format: format)
      image = renderer.image { _ in
        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
      }
    } else {
      image = nil
    }

    guard let image else { return false }
    UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
    return true
  }
}

struct VisualizerSnapshotHost<Content: View>: UIViewControllerRepresentable {
  let snapshotter: VisualizerSnapshotter
  @ViewBuilder let content: () -> Content

  func makeUIViewController(context: Context) -> UIHostingController<Content> {
    let controller = UIHostingController(rootView: content())
    controller.view.backgroundColor = .clear
    snapshotter.captureView = controller.view
    return controller
  }

  func updateUIViewController(_ uiViewController: UIHostingController<Content>, context: Context) {
    uiViewController.rootView = content()
    snapshotter.captureView = uiViewController.view
  }
}
