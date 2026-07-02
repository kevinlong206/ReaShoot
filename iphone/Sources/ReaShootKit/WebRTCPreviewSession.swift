#if os(iOS)
import AVFoundation
import Foundation
import LiveKitWebRTC

final class WebRTCPreviewSession: NSObject {
    private let factory = LKRTCPeerConnectionFactory()
    private let queue = DispatchQueue(label: "com.kevinlong.reashoot.webrtc-preview")
    private var peerConnection: LKRTCPeerConnection?
    private var videoSource: LKRTCVideoSource?
    private var capturer: LKRTCVideoCapturer?
    private var adaptedWidth = 0
    private var adaptedHeight = 0

    func start(offerSDP: String) async throws -> String {
        stop()

        let configuration = LKRTCConfiguration()
        configuration.sdpSemantics = .unifiedPlan
        configuration.iceServers = []

        let constraints = LKRTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peerConnection = factory.peerConnection(with: configuration, constraints: constraints, delegate: nil) else {
            throw WebRTCPreviewError.connectionFailed
        }
        let source = factory.videoSource()
        source.adaptOutputFormat(toWidth: 640, height: 360, fps: 10)
        adaptedWidth = 640
        adaptedHeight = 360
        let track = factory.videoTrack(with: source, trackId: "iphone-preview-video")
        _ = peerConnection.add(track, streamIds: ["iphone-preview"])

        self.peerConnection = peerConnection
        self.videoSource = source
        self.capturer = LKRTCVideoCapturer(delegate: source)

        let offer = LKRTCSessionDescription(type: .offer, sdp: offerSDP)
        try await setRemoteDescription(offer, on: peerConnection)
        let answer = try await makeAnswer(on: peerConnection, constraints: constraints)
        try await setLocalDescription(answer, on: peerConnection)
        try await waitForIceGathering(on: peerConnection)
        return peerConnection.localDescription?.sdp ?? answer.sdp
    }

    func stop() {
        peerConnection?.close()
        peerConnection = nil
        videoSource = nil
        capturer = nil
        adaptedWidth = 0
        adaptedHeight = 0
    }

    func addIceCandidate(sdp: String, sdpMid: String?, sdpMLineIndex: Int32) {
        guard let peerConnection else {
            return
        }
        let candidate = LKRTCIceCandidate(sdp: sdp, sdpMLineIndex: sdpMLineIndex, sdpMid: sdpMid)
        peerConnection.add(candidate) { _ in }
    }

    func consume(pixelBuffer: CVPixelBuffer, timestamp: CMTime) {
        guard let source = videoSource,
              let capturer = capturer else {
            return
        }
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        queue.async { [weak self] in
            guard let self else {
                return
            }
            if width > 0, height > 0, width != self.adaptedWidth || height != self.adaptedHeight {
                source.adaptOutputFormat(toWidth: Int32(width), height: Int32(height), fps: 10)
                self.adaptedWidth = width
                self.adaptedHeight = height
            }
            let timestampNs = timestamp.isValid ? Int64(CMTimeGetSeconds(timestamp) * 1_000_000_000) : Int64(Date().timeIntervalSince1970 * 1_000_000_000)
            let buffer = LKRTCCVPixelBuffer(pixelBuffer: pixelBuffer)
            let frame = LKRTCVideoFrame(buffer: buffer, rotation: ._0, timeStampNs: timestampNs)
            source.capturer(capturer, didCapture: frame)
        }
    }

    private func setRemoteDescription(_ description: LKRTCSessionDescription, on peerConnection: LKRTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setRemoteDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func setLocalDescription(_ description: LKRTCSessionDescription, on peerConnection: LKRTCPeerConnection) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peerConnection.setLocalDescription(description) { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func makeAnswer(on peerConnection: LKRTCPeerConnection, constraints: LKRTCMediaConstraints) async throws -> LKRTCSessionDescription {
        try await withCheckedThrowingContinuation { continuation in
            peerConnection.answer(for: constraints) { answer, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let answer {
                    continuation.resume(returning: answer)
                } else {
                    continuation.resume(throwing: WebRTCPreviewError.answerFailed)
                }
            }
        }
    }

    private func waitForIceGathering(on peerConnection: LKRTCPeerConnection) async throws {
        let deadline = Date().addingTimeInterval(3.0)
        while peerConnection.iceGatheringState != .complete {
            if Date() > deadline {
                return
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
    }
}

enum WebRTCPreviewError: Error, LocalizedError {
    case connectionFailed
    case answerFailed

    var errorDescription: String? {
        switch self {
        case .connectionFailed:
            return "Could not create the WebRTC preview connection."
        case .answerFailed:
            return "Could not create a WebRTC preview answer."
        }
    }
}
#endif
