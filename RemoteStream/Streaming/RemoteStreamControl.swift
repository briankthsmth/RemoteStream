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
//  RemoteStreamControl.swift
//  RemoteStream
//
//  Created by Brian Smith on 10/15/20.
//

import Foundation
import Metal
import CoreVideo
import os
import CoreImage

public class RemoteStreamControl: ObservableObject {
    // MARK: Public Interface
    // MARK: Types
    public typealias ServerConfig = (host: String, port: Int, path: String)
    
    public struct Buffer {
        public let pixelBuffer: CVPixelBuffer
        public let timeStamp: TimeInterval
        
        init(pixelBuffer: CVPixelBuffer, timeStamp: TimeInterval) {
            self.pixelBuffer = pixelBuffer
            self.timeStamp = timeStamp
        }
    }
        
    // MARK: Properties
    @Published public var streaming: Bool = false

    public var buffers: AsyncStream<Buffer> {
        AsyncStream { continuation in
            let id = UUID()
            streamer.addHandler(by: id) { buffer in
                continuation.yield(buffer)
            }
            continuation.onTermination = { @Sendable _ in
                self.streamer.removeHandler(by: id)
            }
        }
    }
    
   // MARK: Methods
    public init() {}
    
    public func connect(with config: ServerConfig) throws {
        stream = RemoteStreamAdapter(location: "rtsp://\(config.host):\(config.port)/\(config.path)") { [weak self] (data, size, width, height) in
            autoreleasepool {
                guard let self = self else { return}
                
                var optionalPixelBuffer: CVPixelBuffer?
                let pixelBufferAttributes: [String : Any] = [
                    kCVPixelBufferMetalCompatibilityKey as String : true,
                    kCVPixelBufferIOSurfacePropertiesKey  as String : [String : Any]()
                ]
                let status = CVPixelBufferCreate(kCFAllocatorDefault,
                                                 width,
                                                 height,
                                                 kCVPixelFormatType_32BGRA,
                                                 pixelBufferAttributes as CFDictionary,
                                                 &optionalPixelBuffer)
                guard
                    status == kCVReturnSuccess,
                    let pixelBuffer = optionalPixelBuffer
                else {
                    os_log("Failed to create CVPixelBuffer: \(status)")
                    return
                }
                
                CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
                let pixels = CVPixelBufferGetBaseAddress(pixelBuffer)
                memcpy(pixels, data, Int(size))
                CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: 0))
                
                self.process(pixelBuffer)
            }}
        
        stream?.connect()
    }
    
    public func disconnect() async {
        await pause()
        stream?.disconnect()
        stream = nil
    }
    
    public func play() {
        guard
            let stream = stream,
            !streaming
        else {
            return
        }
        stream.play()
        streaming = true
    }
    
    public func pause() async {
        guard
            let stream = stream,
            streaming
        else {
            return
        }
        stream.pause()
        streaming = false
    }
    
    public func makePNG() async -> Data? {
        var iterator = buffers.makeAsyncIterator()
        guard
            let halfScaleFilter = CIFilter(name: "CILanczosScaleTransform"),
            let buffer = await iterator.next()
        else {
            return nil
        }
        
        halfScaleFilter.setValue(0.5, forKey: kCIInputScaleKey)
        let image = CIImage(cvPixelBuffer: buffer.pixelBuffer)
        halfScaleFilter.setValue(image, forKey: kCIInputImageKey)
        guard let scaledImage = halfScaleFilter.outputImage else { return nil }
        
        return CIContext().pngRepresentation(of: scaledImage,
                                             format: .RGBA8,
                                             colorSpace: CGColorSpaceCreateDeviceRGB(),
                                             options: [:])
    }

    // MARK: Private Interface
    // MARK: Types
    private class Steamer {
        var handlers: [UUID : (Buffer) -> Void] = [:]
        
        func addHandler(by id: UUID, handler: @escaping (Buffer) -> Void) {
            handlers[id] = handler
        }
        
        func removeHandler(by id: UUID) {
            handlers.removeValue(forKey: id)
        }
        
        func streamNext(_ buffer: Buffer) {
            handlers.values.forEach { $0(buffer) }
        }
    }
    
    // MARK: Properties
    private var stream: RemoteStreamAdapter?
    private let streamer = Steamer()
    
    // MARK: Methods
    private func process(_ pixelBuffer: CVPixelBuffer) {
        Task() { @MainActor in
            let newBuffer = Buffer(pixelBuffer: pixelBuffer,
                                   timeStamp: Date.now.timeIntervalSinceReferenceDate)
            self.streamer.streamNext(newBuffer)
        }
    }
}
