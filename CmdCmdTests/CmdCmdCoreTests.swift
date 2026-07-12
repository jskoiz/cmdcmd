import ImageIO
import UniformTypeIdentifiers
import UIKit
import XCTest
@testable import CmdCmd

@MainActor
final class CmdCmdCoreTests: XCTestCase {
    func testExternalPairDeepLinkIsRejected() {
        let url = URL(string: "cmdcmd://pair?e=192.168.1.2:8787&t=secret")!
        XCTAssertNil(AppDeepLink.parse(url))
        XCTAssertEqual(AppDeepLink.parse(URL(string: "cmdcmd://settings")!), .settings)
    }

    func testCompactPairingLinkStillParsesScannerPayload() {
        let pairing = PairingLink.parse("cmdcmd://pair?e=192.168.1.2:8787&t=secret")
        XCTAssertEqual(pairing?.endpoint, "http://192.168.1.2:8787/v1/captures")
        XCTAssertEqual(pairing?.token, "secret")
    }

    func testPNGPreparationKeepsMatchingBytesAndFilename() throws {
        let prepared = try ImageProcessor.prepare(
            data: try imageData(type: .png),
            filename: "capture.jpeg"
        )

        XCTAssertEqual(prepared.mimeType, "image/png")
        XCTAssertEqual(prepared.filename, "capture.png")
        XCTAssertTrue(prepared.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        XCTAssertEqual(prepared.pixelWidth, 6)
        XCTAssertEqual(prepared.pixelHeight, 4)
        XCTAssertNotNil(prepared.thumbnailData)
    }

    func testJPEGPreparationKeepsMatchingBytesAndFilename() throws {
        let prepared = try ImageProcessor.prepare(
            data: try imageData(type: .jpeg),
            filename: "capture.png"
        )

        XCTAssertEqual(prepared.mimeType, "image/jpeg")
        XCTAssertEqual(prepared.filename, "capture.jpg")
        XCTAssertTrue(prepared.data.starts(with: [0xFF, 0xD8, 0xFF]))
        XCTAssertEqual(prepared.pixelWidth, 6)
        XCTAssertEqual(prepared.pixelHeight, 4)
    }

    func testHEICPreparationTranscodesToMatchingCanonicalType() throws {
        let prepared = try ImageProcessor.prepare(
            data: try imageData(type: .heic),
            filename: "capture.heic"
        )

        XCTAssertTrue(["image/png", "image/jpeg"].contains(prepared.mimeType))
        if prepared.mimeType == "image/png" {
            XCTAssertEqual(prepared.filename, "capture.png")
            XCTAssertTrue(prepared.data.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        } else {
            XCTAssertEqual(prepared.filename, "capture.jpg")
            XCTAssertTrue(prepared.data.starts(with: [0xFF, 0xD8, 0xFF]))
        }
        XCTAssertEqual(prepared.pixelWidth, 6)
        XCTAssertEqual(prepared.pixelHeight, 4)
    }

    func testOversizedTranscodedImageIsReducedBelowUploadLimit() throws {
        let sourceData = try noisyAlphaPNG(width: 1_900, height: 1_900)
        XCTAssertGreaterThan(sourceData.count, 7_500_000)

        let prepared = try ImageProcessor.prepare(
            data: sourceData,
            filename: "oversized.png"
        )

        XCTAssertLessThanOrEqual(prepared.data.count, 7_500_000)
        XCTAssertLessThan(max(prepared.pixelWidth, prepared.pixelHeight), 1_900)
        XCTAssertEqual(prepared.mimeType, "image/png")
    }

    func testOCRTimeoutCancelsAndJoinsWorker() async throws {
        let probe = CancellationProbe()
        let report = try await OCRService.report(
            from: Data([0x01]),
            timeoutNanoseconds: 5_000_000
        ) { _, cancellation in
            probe.markStarted()
            while !cancellation.isCancelled {
                await Task.yield()
            }
            probe.markFinished()
            throw CancellationError()
        }

        XCTAssertTrue(report.timedOut)
        XCTAssertTrue(probe.started)
        XCTAssertTrue(probe.finished)
    }

    func testRelayUploadRequestHasFiniteDeadline() throws {
        let client = RelayClient(
            settings: relaySettings,
            sendRequestTimeoutSeconds: 12.5
        )

        let request = try client.uploadRequest(for: relayPayload)

        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.timeoutInterval, 12.5)
        XCTAssertTrue(request.timeoutInterval.isFinite)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertNotNil(request.httpBody)
    }

    func testRelayStatusRequestIsBoundedByRequestAndOverallDeadlines() {
        let client = RelayClient(
            settings: relaySettings,
            statusRequestTimeoutSeconds: 5
        )
        let statusURL = URL(string: "http://192.168.1.2:8787/v1/captures/id/status")!

        let requestLimited = client.deliveryStatusRequest(
            from: statusURL,
            remainingTime: 30
        )
        let deadlineLimited = client.deliveryStatusRequest(
            from: statusURL,
            remainingTime: 1.25
        )

        XCTAssertEqual(requestLimited.httpMethod, "GET")
        XCTAssertEqual(requestLimited.timeoutInterval, 5)
        XCTAssertTrue(requestLimited.timeoutInterval.isFinite)
        XCTAssertEqual(deadlineLimited.timeoutInterval, 1.25)
        XCTAssertEqual(deadlineLimited.value(forHTTPHeaderField: "Authorization"), "Bearer token")
    }

    func testShareRetryReloadsAfterLoadFailure() async {
        var loadAttempts = 0
        let image = SharedCaptureImage(data: Data([0x01]), filename: "one.png")
        let coordinator = ShareBatchCoordinator(
            successDelayNanoseconds: 0,
            loadInput: {
                loadAttempts += 1
                if loadAttempts == 1 {
                    throw TestError.failed
                }
                return SharedCaptureInput(images: [image])
            },
            submit: { image, _, _, _ in
                Self.record(status: .sent, filename: image.filename)
            },
            endpointFailure: { nil },
            finish: {}
        )

        coordinator.start()
        await coordinator.waitUntilIdle()
        XCTAssertTrue(coordinator.phase.canRetry)

        coordinator.retry()
        await coordinator.waitUntilIdle()
        XCTAssertEqual(coordinator.phase, .sent(1))
        XCTAssertEqual(loadAttempts, 2)
    }

    func testShareRetryResumesAtFirstUnsentImage() async {
        let images = [
            SharedCaptureImage(data: Data([0x01]), filename: "one.png"),
            SharedCaptureImage(data: Data([0x02]), filename: "two.png")
        ]
        var attemptedFilenames: [String] = []
        let coordinator = ShareBatchCoordinator(
            successDelayNanoseconds: 0,
            loadInput: { SharedCaptureInput(images: images) },
            submit: { image, _, _, _ in
                attemptedFilenames.append(image.filename)
                let shouldFail = image.filename == "two.png" && attemptedFilenames.count == 2
                return Self.record(
                    status: shouldFail ? .failed : .sent,
                    filename: image.filename
                )
            },
            endpointFailure: { nil },
            finish: {}
        )

        coordinator.start()
        await coordinator.waitUntilIdle()
        XCTAssertTrue(coordinator.phase.canRetry)

        coordinator.retry()
        await coordinator.waitUntilIdle()
        XCTAssertEqual(coordinator.phase, .sent(2))
        XCTAssertEqual(attemptedFilenames, ["one.png", "two.png", "two.png"])
    }

    func testAcceptedUnconfirmedCaptureIsPendingAndNotRetryable() async {
        let image = SharedCaptureImage(data: Data([0x01]), filename: "one.png")
        var submissionCount = 0
        let coordinator = ShareBatchCoordinator(
            successDelayNanoseconds: 0,
            loadInput: { SharedCaptureInput(images: [image]) },
            submit: { image, _, _, _ in
                submissionCount += 1
                return Self.record(
                    status: .sending,
                    message: "Delivery confirmation pending",
                    filename: image.filename
                )
            },
            endpointFailure: { nil },
            finish: {}
        )

        coordinator.start()
        await coordinator.waitUntilIdle()

        XCTAssertEqual(coordinator.phase, .pending("Delivery confirmation pending"))
        XCTAssertFalse(coordinator.phase.canRetry)
        coordinator.retry()
        await coordinator.waitUntilIdle()
        XCTAssertEqual(submissionCount, 1)
    }

    func testAcceptedUnconfirmedCaptureDoesNotStopRemainingImages() async {
        let images = [
            SharedCaptureImage(data: Data([0x01]), filename: "one.png"),
            SharedCaptureImage(data: Data([0x02]), filename: "two.png"),
            SharedCaptureImage(data: Data([0x03]), filename: "three.png")
        ]
        var attemptedFilenames: [String] = []
        var didFinish = false
        let coordinator = ShareBatchCoordinator(
            successDelayNanoseconds: 0,
            loadInput: { SharedCaptureInput(images: images) },
            submit: { image, _, index, _ in
                attemptedFilenames.append(image.filename)
                return Self.record(
                    status: index == 0 ? .sending : .sent,
                    message: index == 0 ? "Delivery confirmation pending" : "",
                    filename: image.filename
                )
            },
            endpointFailure: { nil },
            finish: { didFinish = true }
        )

        coordinator.start()
        await coordinator.waitUntilIdle()

        XCTAssertEqual(attemptedFilenames, ["one.png", "two.png", "three.png"])
        XCTAssertEqual(
            coordinator.phase,
            .pending("Accepted 3 of 3. Delivery confirmation is pending for 1 item.")
        )
        XCTAssertFalse(coordinator.phase.canRetry)
        XCTAssertFalse(didFinish)
    }

    func testShareLoadDeadlineReturnsWhenLoaderNeverCompletes() async {
        let loadGate = NonCooperativeLoadGate()
        let coordinator = ShareBatchCoordinator(
            loadTimeoutNanoseconds: 5_000_000,
            successDelayNanoseconds: 0,
            loadInput: {
                await loadGate.wait()
            },
            submit: { image, _, _, _ in
                Self.record(status: .sent, filename: image.filename)
            },
            endpointFailure: { nil },
            finish: {}
        )

        coordinator.start()
        await coordinator.waitUntilIdle()

        XCTAssertEqual(
            coordinator.phase,
            .failed("Couldn't load the shared image. Close and try sharing again.")
        )
        XCTAssertTrue(coordinator.phase.canRetry)

        loadGate.release(SharedCaptureInput())
        await Task.yield()
        XCTAssertEqual(
            coordinator.phase,
            .failed("Couldn't load the shared image. Close and try sharing again.")
        )
    }

    private static func record(
        status: CaptureStatus,
        message: String = "",
        filename: String
    ) -> CaptureRecord {
        CaptureRecord(
            source: .shareExtension,
            userNote: "",
            recognizedText: "",
            status: status,
            statusMessage: message,
            endpointHost: nil,
            imageFilename: filename,
            thumbnailData: nil
        )
    }

    private var relaySettings: RelaySettings {
        RelaySettings(
            endpoint: "http://192.168.1.2:8787/v1/captures",
            apiToken: "token",
            defaultContext: "",
            includeRecognizedText: false
        )
    }

    private var relayPayload: CaptureUploadPayload {
        CaptureUploadPayload(
            schemaVersion: 2,
            captureId: UUID(uuidString: "AD734B9A-5D93-4D23-819E-F0BE8EE0A196")!,
            createdAt: Date(timeIntervalSince1970: 0),
            source: CaptureSource.mainApp.rawValue,
            sourceDetail: "",
            screenshotContext: ScreenshotContext(
                capturedAt: nil,
                preparedAt: Date(timeIntervalSince1970: 0),
                timeZoneIdentifier: "UTC",
                source: CaptureSource.mainApp.rawValue,
                sourceDetail: "",
                imageFilename: "capture.png",
                imageMimeType: "image/png",
                pixelWidth: 1,
                pixelHeight: 1,
                originalImageBytes: 1,
                uploadImageBytes: 1,
                ocrEnabled: false,
                ocrDurationMs: nil,
                ocrLineCount: 0,
                ocrCharacterCount: 0,
                ocrTimedOut: false,
                ocrAverageConfidence: nil,
                visibleApp: nil
            ),
            context: "",
            recognizedText: "",
            imageFilename: "capture.png",
            imageMimeType: "image/png",
            imageBase64: "AA=="
        )
    }

    private func imageData(type: UTType) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let image = UIGraphicsImageRenderer(
            size: CGSize(width: 6, height: 4),
            format: format
        ).image { context in
            UIColor.red.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 6, height: 4))
        }

        if type == .png {
            return try XCTUnwrap(image.pngData())
        }
        if type == .jpeg {
            return try XCTUnwrap(image.jpegData(compressionQuality: 0.9))
        }

        let data = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, try XCTUnwrap(image.cgImage), nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return data as Data
    }

    private func noisyAlphaPNG(width: Int, height: Int) throws -> Data {
        var pixelData = Data(count: width * height * 4)
        pixelData.withUnsafeMutableBytes { rawBuffer in
            let pixels = rawBuffer.bindMemory(to: UInt8.self)
            var state: UInt64 = 0x4D595DF4D0F33173
            for index in stride(from: 0, to: pixels.count, by: 4) {
                state = state &* 6_364_136_223_846_793_005 &+ 1
                pixels[index] = UInt8(truncatingIfNeeded: state >> 24)
                state = state &* 6_364_136_223_846_793_005 &+ 1
                pixels[index + 1] = UInt8(truncatingIfNeeded: state >> 24)
                state = state &* 6_364_136_223_846_793_005 &+ 1
                pixels[index + 2] = UInt8(truncatingIfNeeded: state >> 24)
                state = state &* 6_364_136_223_846_793_005 &+ 1
                pixels[index + 3] = UInt8(truncatingIfNeeded: state >> 24)
            }
        }

        let provider = try XCTUnwrap(CGDataProvider(data: pixelData as CFData))
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
            .union(.byteOrder32Big)
        let image = try XCTUnwrap(
            CGImage(
                width: width,
                height: height,
                bitsPerComponent: 8,
                bitsPerPixel: 32,
                bytesPerRow: width * 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: bitmapInfo,
                provider: provider,
                decode: nil,
                shouldInterpolate: false,
                intent: .defaultIntent
            )
        )

        let encoded = NSMutableData()
        let destination = try XCTUnwrap(
            CGImageDestinationCreateWithData(encoded, UTType.png.identifier as CFString, 1, nil)
        )
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return encoded as Data
    }
}

private enum TestError: LocalizedError {
    case failed

    var errorDescription: String? {
        "Test failure"
    }
}

private final class CancellationProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var _started = false
    private var _finished = false

    var started: Bool { lock.withLock { _started } }
    var finished: Bool { lock.withLock { _finished } }

    func markStarted() {
        lock.withLock { _started = true }
    }

    func markFinished() {
        lock.withLock { _finished = true }
    }
}

private final class NonCooperativeLoadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<SharedCaptureInput, Never>?
    private var releasedInput: SharedCaptureInput?

    func wait() async -> SharedCaptureInput {
        await withCheckedContinuation { continuation in
            let releasedInput = lock.withLock { () -> SharedCaptureInput? in
                if let releasedInput = self.releasedInput {
                    return releasedInput
                }
                self.continuation = continuation
                return nil
            }

            if let releasedInput {
                continuation.resume(returning: releasedInput)
            }
        }
    }

    func release(_ input: SharedCaptureInput) {
        let continuation = lock.withLock { () -> CheckedContinuation<SharedCaptureInput, Never>? in
            guard self.releasedInput == nil else {
                return nil
            }
            releasedInput = input
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
        continuation?.resume(returning: input)
    }
}
