//
//  UIImage+Extensions.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 3/14/26.
//

import Foundation
import UIKit
import Accelerate

extension UIImage {
  func calculateAverageLuminance() -> Float? {
    guard let cgImage = self.cgImage else { return nil }
    
    guard var format = vImage_CGImageFormat(bitsPerComponent: 8,
                                            bitsPerPixel: 32,
                                            colorSpace: CGColorSpaceCreateDeviceRGB(),
                                            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.first.rawValue),
                                            renderingIntent: .defaultIntent) else { return nil }
    var sourceBuffer = vImage_Buffer()
    defer { free(sourceBuffer.data) }
    
    var error = vImageBuffer_InitWithCGImage(&sourceBuffer,
                                             &format,
                                             nil,
                                             cgImage,
                                             vImage_Flags(kvImageNoFlags))
    guard error == kvImageNoError else { return nil }
    
    var destBuffer = vImage_Buffer()
    defer { free(destBuffer.data) }
    
    error = vImageBuffer_Init(&destBuffer,
                              sourceBuffer.height,
                              sourceBuffer.width, 8,
                              vImage_Flags(kvImageNoFlags))
    guard error == kvImageNoError else { return nil }
    
    let divisor: Int32 = 10000
    let fR: Int16 = 2126
    let fG: Int16 = 7152
    let fB: Int16 = 722
    var matrix: [Int16] = [fR, fG, fB, 0]
    
    vImageMatrixMultiply_ARGB8888ToPlanar8(&sourceBuffer, &destBuffer, &matrix, divisor, nil, 0, vImage_Flags(kvImageNoFlags))

    let pixelCount = Int(destBuffer.width * destBuffer.height)
    let pixels = destBuffer.data.assumingMemoryBound(to: UInt8.self)
    
    var floatPixels = [Float](repeating: 0, count: pixelCount)
    vDSP_vfltu8(pixels, 1, &floatPixels, 1, vDSP_Length(pixelCount))
    
    var mean: Float = 0
    vDSP_meanv(floatPixels, 1, &mean, vDSP_Length(pixelCount))
    
    return mean / 255.0
  }
}
