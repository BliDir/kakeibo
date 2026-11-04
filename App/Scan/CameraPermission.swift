import AVFoundation

/// Camera access, asked for only when the user taps "Scan receipt".
enum CameraPermission {
    /// True when the camera may be used, asking the user the first time.
    static func request() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }
}
