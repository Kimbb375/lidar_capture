import ARKit
import UIKit
import CoreImage

/// Saves, at about 5 frames per second, the camera image, the LiDAR depth map, its confidence map and the camera pose.
/// Output (Files app > LidarCapture > capture_<time>/): meta.json, rgb/*.jpg, depth/*.f32 (Float32 metres), conf/*.u8 (0 low, 1 mid, 2 high).
final class Recorder: NSObject, ObservableObject, ARSessionDelegate {
    let session = ARSession()
    @Published var recording = false
    @Published var status = "ready"

    private var dir: URL?
    private var frames: [[String: Any]] = []
    private var rgbSize = [0, 0]
    private var lastSave: TimeInterval = 0
    private let interval = 0.2
    private let queue = DispatchQueue(label: "capture.write")
    private let busy = DispatchSemaphore(value: 1)                          // drop a frame when the writer is behind: ARKit stalls if its buffers are kept
    private let ci = CIContext()

    override init() {
        super.init()
        session.delegate = self
        let cfg = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            cfg.frameSemantics = .sceneDepth
        } else {
            status = "no LiDAR depth on this device"
        }
        session.run(cfg)
    }

    func toggle() {
        if recording { stop() } else { start() }
    }

    private func start() {
        let f = DateFormatter(); f.dateFormat = "yyyyMMdd_HHmmss"
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let d = docs.appendingPathComponent("capture_" + f.string(from: Date()))
        for sub in ["rgb", "depth", "conf"] {
            try? FileManager.default.createDirectory(at: d.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        dir = d; frames = []; lastSave = 0
        recording = true
        status = "recording..."
    }

    private func stop() {
        recording = false
        queue.async { [self] in                                             // after the pending frame is written
            guard let d = dir else { return }
            let meta: [String: Any] = ["format": "arkit-lidar-v1", "rgb_size": rgbSize, "frames": frames]
            if let data = try? JSONSerialization.data(withJSONObject: meta) {
                try? data.write(to: d.appendingPathComponent("meta.json"))
            }
            DispatchQueue.main.async { self.status = "saved \(self.frames.count) frames: \(d.lastPathComponent)" }
        }
    }

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        guard recording, let depth = frame.sceneDepth, frame.timestamp - lastSave >= interval else { return }
        guard busy.wait(timeout: .now()) == .success else { return }
        lastSave = frame.timestamp

        let n = frames.count + 1
        let dBytes = copy(depth.depthMap, bytesPerPixel: 4)
        let cBytes = depth.confidenceMap.map { copy($0, bytesPerPixel: 1) }
        let image = frame.capturedImage                                     // retained only until the JPEG is written
        let T = frame.camera.transform
        let K = frame.camera.intrinsics
        let res = frame.camera.imageResolution
        let pose = (0..<4).flatMap { c in (0..<4).map { r in T[c][r] } }    // column-major
        let name = String(format: "%06d", n)
        let entry: [String: Any] = [
            "id": n, "t": frame.timestamp, "T": pose,
            "K": [K[0][0], K[1][1], K[2][0], K[2][1]],                      // fx, fy, cx, cy in rgb pixels
            "rgb": "rgb/\(name).jpg", "depth": "depth/\(name).f32", "conf": "conf/\(name).u8",
            "depth_size": [dBytes.1, dBytes.2],
        ]
        frames.append(entry)
        rgbSize = [Int(res.width), Int(res.height)]
        let d = dir!

        queue.async { [self] in
            defer { busy.signal() }
            try? dBytes.0.write(to: d.appendingPathComponent("depth/\(name).f32"))
            if let c = cBytes { try? c.0.write(to: d.appendingPathComponent("conf/\(name).u8")) }
            let img = CIImage(cvPixelBuffer: image)
            if let jpg = ci.jpegRepresentation(of: img, colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, options: [:]) {
                try? jpg.write(to: d.appendingPathComponent("rgb/\(name).jpg"))
            }
            DispatchQueue.main.async { self.status = "recording: \(n) frames" }
        }
    }

    /// Copy a pixel buffer row by row (rows may be padded) -> (bytes, width, height).
    private func copy(_ pb: CVPixelBuffer, bytesPerPixel: Int) -> (Data, Int, Int) {
        CVPixelBufferLockBaseAddress(pb, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(pb, .readOnly) }
        let w = CVPixelBufferGetWidth(pb), h = CVPixelBufferGetHeight(pb), bpr = CVPixelBufferGetBytesPerRow(pb)
        let base = CVPixelBufferGetBaseAddress(pb)!
        var out = Data(capacity: w * h * bytesPerPixel)
        for y in 0..<h {
            out.append(Data(bytes: base + y * bpr, count: w * bytesPerPixel))
        }
        return (out, w, h)
    }
}
