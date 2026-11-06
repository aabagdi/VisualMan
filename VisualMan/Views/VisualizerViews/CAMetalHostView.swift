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
    let size = CGSize(width: bounds.width * scale,
                      height: bounds.height * scale)
    guard size.width > 0, size.height > 0 else { return }
    if metalLayer.drawableSize != size {
      metalLayer.drawableSize = size
    }
  }
}

#endif
