//
//  UIDocumentBrowserViewControllerRepresentable.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/13/26.
//

import SwiftUI
internal import UniformTypeIdentifiers

struct UIDocumentBrowserViewControllerRepresentable: UIViewControllerRepresentable {
  var onDocumentPicked: (URL) -> Void
  var showVisualizerButton: Bool = false
  var onVisualizerTapped: (() -> Void)? = nil
  
  func makeCoordinator() -> Coordinator {
    Coordinator(onDocumentPicked: onDocumentPicked, onVisualizerTapped: onVisualizerTapped)
  }
  
  func makeUIViewController(context: Context) -> DocumentBrowserContainerViewController {
    let browser = UIDocumentBrowserViewController(forOpening: [.aiff, .mp3, .wav, .mpeg4Audio, .audio])
    browser.allowsDocumentCreation = false
    browser.allowsPickingMultipleItems = false
    browser.delegate = context.coordinator
    updateVisualizerButton(on: browser, context: context)
    
    let container = DocumentBrowserContainerViewController(browserController: browser)
    context.coordinator.browserController = browser
    return container
  }
  
  func updateUIViewController(_ uiViewController: DocumentBrowserContainerViewController, context: Context) {
    context.coordinator.onVisualizerTapped = onVisualizerTapped
    if let browser = context.coordinator.browserController {
      updateVisualizerButton(on: browser, context: context)
    }
  }
  
  private func updateVisualizerButton(on controller: UIDocumentBrowserViewController, context: Context) {
    if showVisualizerButton {
      let action = UIAction { _ in
        context.coordinator.onVisualizerTapped?()
      }
      let button = UIBarButtonItem(primaryAction: action)
      let barsFill = UIImage(systemName: "play.fill")
      button.image = barsFill
      controller.additionalTrailingNavigationBarButtonItems = [button]
    } else {
      controller.additionalTrailingNavigationBarButtonItems = []
    }
  }
  
  class Coordinator: NSObject, UIDocumentBrowserViewControllerDelegate {
    var onDocumentPicked: (URL) -> Void
    var onVisualizerTapped: (() -> Void)?
    weak var browserController: UIDocumentBrowserViewController?
    
    init(onDocumentPicked: @escaping (URL) -> Void, onVisualizerTapped: (() -> Void)?) {
      self.onDocumentPicked = onDocumentPicked
      self.onVisualizerTapped = onVisualizerTapped
    }
    
    func documentBrowser(_ controller: UIDocumentBrowserViewController, didPickDocumentsAt documentURLs: [URL]) {
      guard let url = documentURLs.first else { return }
      onDocumentPicked(url)
    }
  }
}

class DocumentBrowserContainerViewController: UIViewController {
  let browserController: UIDocumentBrowserViewController
  
  init(browserController: UIDocumentBrowserViewController) {
    self.browserController = browserController
    super.init(nibName: nil, bundle: nil)
  }
  
  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
  
  override func viewDidLoad() {
    super.viewDidLoad()
    addChild(browserController)
    view.addSubview(browserController.view)
    browserController.view.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      browserController.view.topAnchor.constraint(equalTo: view.topAnchor),
      browserController.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
      browserController.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
      browserController.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
    ])
    browserController.didMove(toParent: self)
  }
  
  override func viewSafeAreaInsetsDidChange() {
    super.viewSafeAreaInsetsDidChange()
    browserController.additionalSafeAreaInsets.bottom = view.safeAreaInsets.bottom
  }
}
