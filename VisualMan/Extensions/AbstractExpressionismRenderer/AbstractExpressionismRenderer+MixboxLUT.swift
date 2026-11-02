//
//  AbstractExpressionismRenderer+MixboxLUT.swift
//  VisualMan
//
//  Created on 11/2/26.
//

#if !targetEnvironment(simulator)
import Foundation
import Metal
import os
import UIKit

extension AbstractExpressionismRenderer {
  static func makeMixboxLUT(device: MTLDevice) -> MTLTexture? {
    guard let png = NSDataAsset(name: "mixbox_lut")?.data else {
      logger.error("mixbox_lut data asset is missing from the asset catalog")
      return nil
    }
    guard var pixels = decodeMixboxPNG(png) else { return nil }
    orientMixboxLUT(&pixels)

    let size = lutSize
    let desc = MTLTextureDescriptor.texture2DDescriptor(
      pixelFormat: .rgba8Unorm, width: size, height: size, mipmapped: false)
    desc.usage = .shaderRead
    desc.storageMode = .shared
    guard let texture = device.makeTexture(descriptor: desc) else {
      logger.error("Could not create the Mixbox LUT texture")
      return nil
    }
    pixels.withUnsafeBytes { buf in
      texture.replace(region: MTLRegionMake2D(0, 0, size, size),
                      mipmapLevel: 0,
                      withBytes: buf.baseAddress!,
                      bytesPerRow: size * 4)
    }
    return texture
  }

  private static let lutSize = 512
  private static let chunkIHDR: [UInt8] = Array("IHDR".utf8)
  private static let chunkIDAT: [UInt8] = Array("IDAT".utf8)
  private static let chunkIEND: [UInt8] = Array("IEND".utf8)

  private static func decodeMixboxPNG(_ png: Data) -> [UInt8]? {
    let signature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
    guard png.count > 8, Array(png.prefix(8)) == signature else {
      logger.error("Mixbox LUT is not a PNG")
      return nil
    }
    var idat = Data()
    var headerOK = false
    var offset = 8
    while offset + 8 <= png.count {
      let length = Int(readUInt32(png, offset))
      let type = Array(png[(offset + 4)..<(offset + 8)])
      let body = (offset + 8)..<(offset + 8 + length)
      guard body.upperBound <= png.count else { break }
      if type == chunkIHDR {
        let w = Int(readUInt32(png, body.lowerBound))
        let h = Int(readUInt32(png, body.lowerBound + 4))
        let bitDepth = png[body.lowerBound + 8]
        let colourType = png[body.lowerBound + 9]
        let interlace = png[body.lowerBound + 12]
        headerOK = (w == lutSize && h == lutSize && bitDepth == 8
                    && colourType == 6 && interlace == 0)
        if !headerOK {
          logger.error("""
            Mixbox LUT layout unexpected: \(w)x\(h) depth \(bitDepth) \
            type \(colourType) interlace \(interlace)
            """)
          return nil
        }
      } else if type == chunkIDAT {
        idat.append(png[body])
      } else if type == chunkIEND {
        break
      }
      offset = body.upperBound + 4
    }
    guard headerOK, idat.count > 6 else {
      logger.error("Mixbox LUT PNG has no usable image data")
      return nil
    }

    let deflate = idat.subdata(in: 2..<(idat.count - 4))
    guard let raw = try? (deflate as NSData).decompressed(using: .zlib) as Data else {
      logger.error("Could not inflate the Mixbox LUT")
      return nil
    }
    return unfilterPNGRows(raw)
  }

  private static func readUInt32(_ d: Data, _ at: Int) -> UInt32 {
    (UInt32(d[at]) << 24) | (UInt32(d[at + 1]) << 16) | (UInt32(d[at + 2]) << 8) | UInt32(d[at + 3])
  }

  private static func unfilterPNGRows(_ raw: Data) -> [UInt8]? {
    let size = lutSize
    let stride = size * 4
    guard raw.count >= (stride + 1) * size else {
      logger.error("Mixbox LUT inflated to \(raw.count) bytes, expected \((stride + 1) * size)")
      return nil
    }
    var out = [UInt8](repeating: 0, count: stride * size)
    let src = [UInt8](raw)
    var pos = 0
    for y in 0..<size {
      let filter = src[pos]; pos += 1
      let rowStart = y * stride
      let prevStart = rowStart - stride
      for x in 0..<stride {
        let v = src[pos + x]
        let a = x >= 4 ? Int(out[rowStart + x - 4]) : 0
        let b = y > 0 ? Int(out[prevStart + x]) : 0
        let c = (x >= 4 && y > 0) ? Int(out[prevStart + x - 4]) : 0
        let predictor: Int
        switch filter {
        case 0: predictor = 0
        case 1: predictor = a
        case 2: predictor = b
        case 3: predictor = (a + b) / 2
        default:
          let p = a + b - c
          let pa = abs(p - a), pb = abs(p - b), pc = abs(p - c)
          predictor = (pa <= pb && pa <= pc) ? a : (pb <= pc ? b : c)
        }
        out[rowStart + x] = UInt8((Int(v) + predictor) & 0xFF)
      }
      pos += stride
    }
    return out
  }
  
  private static func orientMixboxLUT(_ pixels: inout [UInt8]) {
    let size = lutSize
    let bytesPerRow = size * 4
    let bottomLeftBlue = pixels[(size - 1) * bytesPerRow + 2]
    if pixels[2] < 26 && bottomLeftBlue >= 26 {
      var flipped = [UInt8](repeating: 0, count: pixels.count)
      for y in 0..<size {
        let s = (size - 1 - y) * bytesPerRow
        let d = y * bytesPerRow
        flipped.replaceSubrange(d..<(d + bytesPerRow), with: pixels[s..<(s + bytesPerRow)])
      }
      pixels = flipped
      logger.info("Mixbox LUT rows were bottom-up; flipped to top-left origin")
    }
    let u = 128 * bytesPerRow + 326 * 4
    let topLeft = "(\(pixels[0]),\(pixels[1]),\(pixels[2]))"
    let ultra = "(\(pixels[u]),\(pixels[u + 1]),\(pixels[u + 2]))"
    logger.info("Mixbox LUT check: top-left=\(topLeft) ultramarine texel=\(ultra)")
  }
}

#endif
