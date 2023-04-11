//
//  Copyright 2020-2023 Brian Keith Smith
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//
//  RemoteStreamView.swift
//  RemoteStream
//
//  Created by Brian Smith on 10/13/20.
//

import SwiftUI
import MetalKit
import Combine
import os
import simd

#if os(iOS)
typealias ViewRepresentable = UIViewRepresentable
#elseif os(macOS)
typealias ViewRepresentable = NSViewRepresentable
#endif

public struct RemoteStreamView : ViewRepresentable {
    @EnvironmentObject var control: RemoteStreamControl
    
    public init() {
        device = MTLCreateSystemDefaultDevice()
    }

    #if os(iOS)
    public func makeUIView(context: Context) -> MTKView {
        let view = makeView(context: context)
        view.contentScaleFactor = UIScreen.main.scale
        return view
    }
    #elseif os(macOS)
    public func makeNSView(context: Context) -> MTKView {
        return makeView(context: context)
    }
    #endif
    
    func makeView(context: Context) -> MTKView {
        let view = MTKView(frame: .zero, device: device)
        view.framebufferOnly = true
        view.colorPixelFormat = .bgra8Unorm
        view.delegate = context.coordinator
        return view

    }

    #if os(iOS)
    public func updateUIView(_ uiView: MTKView, context: Context) {}
    #elseif os(macOS)
    public func updateNSView(_ nsView: MTKView, context: Context) {}
    #endif
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(control: control, device: device, renderPipelineState: makeRenderPipelineState())
    }

    // MARK: Private Interface
    private let device: MTLDevice?

    private func makeRenderPipelineState() -> MTLRenderPipelineState? {
        guard let device = device else { return nil }
        
        let library: MTLLibrary
        do {
            library = try device.makeDefaultLibrary(bundle: Bundle(for: RemoteStreamControl.self))
        } catch {
            os_log("Failed to load metal shaders.")
            return nil
        }
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipelineDescriptor.depthAttachmentPixelFormat = .invalid
        
        pipelineDescriptor.vertexFunction = library.makeFunction(name: "vertexShader")
        pipelineDescriptor.fragmentFunction = library.makeFunction(name: "samplingShader")
        
        do {
            return try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        }
        catch {
            assertionFailure("Failed creating a render state pipeline. Can't render the texture without one.")
            return nil
        }
    }
}

public class Coordinator: NSObject, MTKViewDelegate {
    init(control: RemoteStreamControl, device: MTLDevice?, renderPipelineState: MTLRenderPipelineState?) {
        self.streamMonitor = StreamMonitor(with: control, device: device, state: renderPipelineState)
        super.init()
    }
    
    public func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        streamMonitor.updateDrawableSize(size)
    }
    
    public func draw(in view: MTKView) {
        streamMonitor.drawBuffer(in: view)
    }
    
    // MARK: Private Interface
    private actor StreamMonitor {
        private let device: MTLDevice?
        private let renderPipelineState: MTLRenderPipelineState?

        private var pixelBuffer: CVPixelBuffer?
        
        private var textureCache: CVMetalTextureCache?
        private var texture: MTLTexture?
        private var metalTexture: CVMetalTexture?

        private var viewportSize: [UInt32] = Array(repeating: 0, count: 2)
        private var vertices: MTLBuffer?
        private var vertextCount: Int = 6
        private var needsVerticesUpdate = true

        init(with control: RemoteStreamControl, device: MTLDevice?, state: MTLRenderPipelineState?) {
            self.device = MTLCreateSystemDefaultDevice()
            renderPipelineState = state
            guard let device = device else { return }
            CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)

            let buffers = control.buffers
            Task() {
                for await buffer in buffers {
                    await process(buffer)
                }
            }
        }
        
        func process(_ buffer: RemoteStreamControl.Buffer) {
            pixelBuffer = buffer.pixelBuffer
            texture = nil
            metalTexture = nil
            
            guard let textureCache = self.textureCache else { return }
            
            var optionalCvMetalTexture: CVMetalTexture?
            let status = CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                                   textureCache,
                                                                   buffer.pixelBuffer,
                                                                   nil,
                                                                   .bgra8Unorm,
                                                                   CVPixelBufferGetWidth(buffer.pixelBuffer),
                                                                   CVPixelBufferGetHeight(buffer.pixelBuffer),
                                                                   0,
                                                                   &optionalCvMetalTexture)
            guard status == kCVReturnSuccess else {
                os_log("Failed to create CVMetalTexture: \(status)")
                return
            }
            
            guard
                let cvMetalTexture = optionalCvMetalTexture,
                let texture = CVMetalTextureGetTexture(cvMetalTexture)
            else {
                os_log("Failed to create metal texture.")
                return
            }
            

            self.metalTexture = cvMetalTexture
            self.texture = texture
            
            if needsVerticesUpdate {
                let textureWidth = texture.width
                let textureHeight = texture.height
                updateVertices(textureWidth: textureWidth, textureHeight: textureHeight)
                needsVerticesUpdate = false
            }
        }
        
        func updateViewPortSize(_ newSize: [UInt32]) {
            viewportSize = newSize
        }
        
        nonisolated func updateDrawableSize(_ newSize: CGSize) {
            Task() {
                await updateViewPortSize([UInt32(newSize.width), UInt32(newSize.height)])
                
            }
        }
        
        nonisolated func drawBuffer(in view: MTKView) {
            Task() {@MainActor in
                guard
                    let vertices = await vertices,
                    let texture = await texture,
                    let renderPipelineState = renderPipelineState,
                    let commandBuffer = device?.makeCommandQueue()?.makeCommandBuffer(),
                    let renderPassDescriptor = view.currentRenderPassDescriptor,
                    let drawable = view.currentDrawable,
                    let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)
                else {
                    return
                }
                
                var viewportSize = await viewportSize
                let vertextCount = await vertextCount
                
                encoder.pushDebugGroup("RenderFrame")
                encoder.setViewport(MTLViewport(originX: 0,
                                                originY: 0,
                                                width: Double(viewportSize[0]),
                                                height: Double(viewportSize[1]),
                                                znear: -1,
                                                zfar: 1))
                encoder.setRenderPipelineState(renderPipelineState)
                encoder.setVertexBuffer(vertices,
                                        offset: 0,
                                        index: VertexInputIndex.Vertices.rawValue)
                encoder.setVertexBytes(&viewportSize,
                                       length: viewportSize.count * MemoryLayout<UInt32>.stride,
                                       index: VertexInputIndex.ViewportSize.rawValue)
                encoder.setFragmentTexture(texture, index: 0)
                encoder.drawPrimitives(type: .triangleStrip,
                                       vertexStart: 0,
                                       vertexCount: vertextCount)
                encoder.popDebugGroup()
                encoder.endEncoding()
                
                commandBuffer.present(drawable)
                commandBuffer.commit()
                
                await updateViewPortSize(viewportSize)
            }
        }
        
        private func updateVertices(textureWidth: Int, textureHeight: Int) {
            let viewportWidth = Float(viewportSize[0])
            let verticeWidth: Float = viewportWidth / 2
            let verticeHeight: Float = (viewportWidth * Float(textureHeight) / Float(textureWidth)) / 2
            let quadVertices: [Float] =
                [
                    verticeWidth, -verticeHeight, 1, 1,
                    -verticeWidth, -verticeHeight, 0, 1,
                    -verticeWidth,  verticeHeight, 0, 0,
                    
                    verticeWidth, -verticeHeight, 1, 1,
                    -verticeWidth,  verticeHeight, 0, 0,
                    verticeWidth,  verticeHeight, 1, 0
                ]
            
            vertices = device?.makeBuffer(bytes: quadVertices,
                                                  length: quadVertices.count * MemoryLayout<Float>.stride,
                                                  options: .storageModeShared)
        }
    }
    
    private var streamMonitor: StreamMonitor
}
