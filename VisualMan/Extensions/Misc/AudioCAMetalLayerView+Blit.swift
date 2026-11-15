//
//  AudioCAMetalLayerView+Blit.swift
//  VisualMan
//
//  Created by Aadit Bagdi on 11/15/26.
//

#if !targetEnvironment(simulator)
import Metal
import os

private nonisolated let blitLogger = Logger(subsystem: "com.VisualMan", category: "AudioMetalView")

extension AudioCAMetalLayerView.Coordinator {
  static func makeBlitResources(device: MTLDevice, pixelFormat: MTLPixelFormat)
  -> (pipeline: (any MTLRenderPipelineState)?, tables: [any MTL4ArgumentTable]) {
    guard let library = device.makeDefaultLibrary() else {
      blitLogger.error("Failed to create default Metal library for blit pipeline")
      return (nil, [])
    }
    do {
      let compiler = try device.makeCompiler(descriptor: MTL4CompilerDescriptor())

      let vertexDesc = MTL4LibraryFunctionDescriptor()
      vertexDesc.name = "blitVertex"
      vertexDesc.library = library

      let fragmentDesc = MTL4LibraryFunctionDescriptor()
      fragmentDesc.name = "blitFragment"
      fragmentDesc.library = library

      let pipelineDesc = MTL4RenderPipelineDescriptor()
      pipelineDesc.vertexFunctionDescriptor = vertexDesc
      pipelineDesc.fragmentFunctionDescriptor = fragmentDesc
      pipelineDesc.colorAttachments[0].pixelFormat = pixelFormat
      let pipeline = try compiler.makeRenderPipelineState(descriptor: pipelineDesc)

      let tableDesc = MTL4ArgumentTableDescriptor()
      tableDesc.maxTextureBindCount = 1
      var tables = [any MTL4ArgumentTable]()
      for _ in 0..<R.maxFramesInFlight {
        tables.append(try device.makeArgumentTable(descriptor: tableDesc))
      }
      return (pipeline, tables)
    } catch {
      blitLogger.error("Failed to create blit pipeline: \(error.localizedDescription)")
      return (nil, [])
    }
  }

  static func makePresentAllocators(device: MTLDevice) -> [any MTL4CommandAllocator] {
    var allocators = [any MTL4CommandAllocator]()
    for _ in 0..<R.maxFramesInFlight {
      guard let allocator = device.makeCommandAllocator() else {
        blitLogger.error("Failed to create present command allocators")
        return []
      }
      allocators.append(allocator)
    }
    return allocators
  }
}

#endif
