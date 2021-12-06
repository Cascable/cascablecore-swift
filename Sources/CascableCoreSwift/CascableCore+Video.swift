import Foundation
import CascableCore

/// Video recording timer types.
public enum VideoRecordingTimerValue {
    /// The timer is counting down towards zero with the given value in seconds (i.e., it's a "time remaining" timer).
    case countingDown(value: TimeInterval)
    /// The timer is counting up from zero with the given value in seconds (i.e., it's a "clip length" timer).
    case countingUp(value: TimeInterval)

    /// Returns the timer's value as a basic string (like "10:47").
    public var asMinutesAndSeconds: String {
        let value: TimeInterval = {
            switch self {
            case .countingDown(let value): return value
            case .countingUp(let value): return value
            }
        }()

        let minutes: Int = max(0, Int(floor(value / 60.0)))
        let seconds: Int = max(0, Int(floor(value.truncatingRemainder(dividingBy: 60.0))))
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// A camera's video recording state.
public enum VideoRecordingState {
    /// The camera isn't recording video.
    case notRecording
    /// The camera is recording video with the given timer.
    case recording(timer: VideoRecordingTimerValue?)
}

public extension CameraVideoRecording {

    /// Returns the video recording state of the camera.
    var videoRecordingState: VideoRecordingState {
        return _videoRecordingState(from: isRecordingVideo, timer: currentVideoTimerValue)
    }
}

internal extension CameraVideoRecording {

    /// Convert the given CascableCore Objective-C API video state values into a `VideoRecordingState`.
    func _videoRecordingState(from isRecording: Bool, timer: VideoTimerValue?) -> VideoRecordingState {
        switch (isRecording, timer) {
        case (false, _): return .notRecording
        case (true, let timer?):
            switch timer.type {
            case .none: return .recording(timer: nil)
            case .countingDown: return .recording(timer: .countingDown(value: timer.value))
            case .countingUp: return .recording(timer: .countingUp(value: timer.value))
            @unknown default: return .recording(timer: nil)
            }
        case (true, _): return .recording(timer: nil)
        }
    }
}

