//
//  SharedKeys.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/24/26.
//

import Sharing

extension SharedKey where Self == AppStorageKey<Bool>.Default {
  static var hapticsEnabled: Self {
    Self[.appStorage("hapticsEnabled"), default: true]
  }

  static var keepsControlsVisible: Self {
    Self[.appStorage("keepsControlsVisible"), default: false]
  }
}

extension SharedKey where Self == AppStorageKey<Double>.Default {
  static var hapticsStrength: Self {
    Self[.appStorage("hapticsStrength"), default: HapticsManager.Constants.defaultStrength]
  }
}

extension SharedKey where Self == AppStorageKey<Bool?> {
  static var reducesFlashingOverride: Self {
    .appStorage("reducesFlashing")
  }
}

extension SharedKey where Self == AppStorageKey<VisualizerIntensity?> {
  static var visualizerIntensityOverride: Self {
    .appStorage("visualizerIntensity")
  }
}
