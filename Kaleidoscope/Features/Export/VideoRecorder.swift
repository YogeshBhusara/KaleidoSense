//
//  VideoRecorder.swift
//  KaleidoSense
//
//  Records the kaleidoscope to an H.264 MP4. Rather than racing the live
//  drawable's lifetime, the recorder drives its own CADisplayLink and, on each
//  tick, asks a provider for a freshly rendered CGImage (via the renderer's
//  off-screen snapshot). This is robust, decoupled from on-screen presentation,
//  and lets us record at a fixed resolution and frame rate.
//

import AVFoundation
import CoreVideo
import Photos
import QuartzCore
import UIKit

@MainActor
final class VideoRecorder: NSObject {

    private var writer: AVAssetWriter?
    private var input: AVAssetWriterInput?
    private var adaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var displayLink: CADisplayLink?

    private var frameProvider: (() -> CGImage?)?
    private var startTime: CFTimeInterval = 0
    private var frameCount: Int64 = 0
    private var fps: Int32 = 30
    private var outputURL: URL?

    private(set) var isRecording = false

    /// Begins recording at the given pixel size and frame rate.
    func start(size: CGSize, fps: Int32 = 30, frameProvider: @escaping () -> CGImage?) throws {
        guard !isRecording else { return }
        self.fps = fps
        self.frameProvider = frameProvider
        self.frameCount = 0

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("KaleidoSense-\(UUID().uuidString).mp4")
        try? FileManager.default.removeItem(at: url)
        outputURL = url

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
        let width = Int(size.width)
        let height = Int(size.height)
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height,
            AVVideoCompressionPropertiesKey: [
                AVVideoAverageBitRateKey: width * height * 8,
                AVVideoMaxKeyFrameIntervalKey: fps
            ]
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        input.expectsMediaDataInRealTime = true

        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input, sourcePixelBufferAttributes: attrs)

        guard writer.canAdd(input) else { throw ExportError.saveFailed }
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        self.writer = writer
        self.input = input
        self.adaptor = adaptor
        self.startTime = CACurrentMediaTime()
        self.isRecording = true

        let link = CADisplayLink(target: self, selector: #selector(captureTick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: Float(fps),
                                                        maximum: Float(fps),
                                                        preferred: Float(fps))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    @objc private func captureTick() {
        guard isRecording,
              let adaptor, let input, input.isReadyForMoreMediaData,
              let cgImage = frameProvider?(),
              let pool = adaptor.pixelBufferPool else { return }

        var pixelBuffer: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer) == kCVReturnSuccess,
              let buffer = pixelBuffer else { return }

        fill(buffer, with: cgImage)

        let time = CMTime(value: frameCount, timescale: fps)
        adaptor.append(buffer, withPresentationTime: time)
        frameCount += 1
    }

    private func fill(_ buffer: CVPixelBuffer, with cgImage: CGImage) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer) else { return }
        let width = CVPixelBufferGetWidth(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let rowBytes = CVPixelBufferGetBytesPerRow(buffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
        guard let ctx = CGContext(data: base, width: width, height: height,
                                  bitsPerComponent: 8, bytesPerRow: rowBytes,
                                  space: colorSpace, bitmapInfo: bitmapInfo) else { return }
        ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    /// Stops recording and returns the finished file URL.
    func stop() async -> URL? {
        guard isRecording else { return nil }
        isRecording = false
        displayLink?.invalidate()
        displayLink = nil

        input?.markAsFinished()
        await writer?.finishWriting()
        let url = outputURL
        writer = nil
        input = nil
        adaptor = nil
        frameProvider = nil
        return url
    }

    /// Saves a recorded movie file to the photo library.
    ///
    /// `nonisolated` so the `performChanges` block is not MainActor-isolated —
    /// Photos runs it on a background queue and a main-actor block would crash
    /// with a libdispatch queue assertion.
    nonisolated static func saveToPhotos(_ url: URL) async throws {
        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.photoPermissionDenied
        }
        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }
    }
}
