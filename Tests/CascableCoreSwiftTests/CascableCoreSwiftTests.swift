import XCTest
@testable import CascableCoreSwift

final class CascableCoreSwiftTests: XCTestCase {

    func testTimerFormatting() {
        // Counting up
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: 0.0).asMinutesAndSeconds, "0:00")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: 1.0).asMinutesAndSeconds, "0:01")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: 10.0).asMinutesAndSeconds, "0:10")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: 59.0).asMinutesAndSeconds, "0:59")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: 59.9999).asMinutesAndSeconds, "0:59")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: 60.0).asMinutesAndSeconds, "1:00")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: 60.0 * 60.0).asMinutesAndSeconds, "60:00")

        // Counting Down
        XCTAssertEqual(VideoRecordingTimerValue.countingDown(value: 0.0).asMinutesAndSeconds, "0:00")
        XCTAssertEqual(VideoRecordingTimerValue.countingDown(value: 1.0).asMinutesAndSeconds, "0:01")
        XCTAssertEqual(VideoRecordingTimerValue.countingDown(value: 10.0).asMinutesAndSeconds, "0:10")
        XCTAssertEqual(VideoRecordingTimerValue.countingDown(value: 59.0).asMinutesAndSeconds, "0:59")
        XCTAssertEqual(VideoRecordingTimerValue.countingDown(value: 59.9999).asMinutesAndSeconds, "0:59")
        XCTAssertEqual(VideoRecordingTimerValue.countingDown(value: 60.0).asMinutesAndSeconds, "1:00")
        XCTAssertEqual(VideoRecordingTimerValue.countingDown(value: 60.0 * 60.0).asMinutesAndSeconds, "60:00")

        // Invalid values
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: -1000.0).asMinutesAndSeconds, "0:00")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: -1.0).asMinutesAndSeconds, "0:00")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: -0.0).asMinutesAndSeconds, "0:00")
        XCTAssertEqual(VideoRecordingTimerValue.countingUp(value: -0.1).asMinutesAndSeconds, "0:00")
    }

}
