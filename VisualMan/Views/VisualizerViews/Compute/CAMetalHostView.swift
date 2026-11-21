//
//  CAMetalHostView.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 4/9/26.
//

#if !targetEnvironment(simulator)
import UIKit
import QuartzCore

final class CAMetalHostView: UIView {
  private static let externalDisplayMaxPixels: CGFloat = 1920 * 1080

  override static var layerClass: AnyClass { CAMetalLayer.self }
  var metalLayer: CAMetalLayer {
    guard let layer = layer as? CAMetalLayer else {
      fatalError("CAMetalHostView.layerClass must be CAMetalLayer")
    }
    return layer
  }

  var onWindowAttach: (() -> Void)?

  override func layoutSubviews() {
    super.layoutSubviews()
    updateDrawableSize()
  }

  override func didMoveToWindow() {
    super.didMoveToWindow()
    if let window {
      metalLayer.contentsScale = window.screen.nativeScale
      updateDrawableSize()
      onWindowAttach?()
    }
  }

  private func updateDrawableSize() {
    let scale = metalLayer.contentsScale
    var size = CGSize(width: bounds.width * scale,
                      height: bounds.height * scale)
    if window?.windowScene?.session.role == .windowExternalDisplayNonInteractive {
      let fit = min(1, Self.externalDisplayMaxPixels / max(size.width * size.height, 1)).squareRoot()
      size = CGSize(width: (size.width * fit).rounded(), height: (size.height * fit).rounded())
    }
    guard size.width > 0, size.height > 0 else { return }
    if metalLayer.drawableSize != size {
      metalLayer.drawableSize = size
    }
  }
}

#endif
