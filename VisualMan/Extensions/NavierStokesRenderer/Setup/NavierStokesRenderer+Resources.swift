//
//  NavierStokesRenderer+Resources.swift
//  VisualMan
//

#if !targetEnvironment(simulator)
import Metal

extension NavierStokesRenderer {
  struct Resources {
    let commandQueue: any MTL4CommandQueue
    let commandBuffer: any MTL4CommandBuffer
    let sharedEvent: MTLSharedEvent
    let allocators: [any MTL4CommandAllocator]
    let uniformBuffers: [MTLBuffer]
    let firstUniformBuffer: MTLBuffer
    let argumentTables: [any MTL4ArgumentTable]
    let gridSize: Int
    let textures: Textures
    let residencySet: MTLResidencySet
    let technicolorLUT: MTLTexture
    let technicolorGrain: MTLTexture
    let stretchStatsBuffer: MTLBuffer
  }

  static func makeResources(device: MTLDevice) -> Resources? {
    guard let commandQueue = device.makeMTL4CommandQueue(),
          let commandBuffer = device.makeCommandBuffer(),
          let sharedEvent = device.makeSharedEvent() else {
      return nil
    }
    sharedEvent.signaledValue = 0

    guard let allocatorsAndBuffers = createAllocatorsAndBuffers(device: device),
          let firstUniformBuffer = allocatorsAndBuffers.buffers.first else { return nil }

    guard let argumentTables = createArgumentTables(device: device) else { return nil }
    let initialGrid = 1024
    guard let textures = createTextures(device: device, width: initialGrid, height: initialGrid),
          let residencySet = createResidencySet(device: device),
          let technicolorLUT = createTechnicolorLUT(device: device),
          let technicolorGrain = createTechnicolorGrain(device: device) else { return nil }
    guard let stretchStatsBuffer = device.makeBuffer(
      length: stretchStatsStride * Int(maxFramesInFlight),
      options: .storageModeShared) else { return nil }
    memset(stretchStatsBuffer.contents(), 0, stretchStatsBuffer.length)

    return Resources(commandQueue: commandQueue,
                     commandBuffer: commandBuffer,
                     sharedEvent: sharedEvent,
                     allocators: allocatorsAndBuffers.allocators,
                     uniformBuffers: allocatorsAndBuffers.buffers,
                     firstUniformBuffer: firstUniformBuffer,
                     argumentTables: argumentTables,
                     gridSize: initialGrid,
                     textures: textures,
                     residencySet: residencySet,
                     technicolorLUT: technicolorLUT,
                     technicolorGrain: technicolorGrain,
                     stretchStatsBuffer: stretchStatsBuffer)
  }
}

#endif
