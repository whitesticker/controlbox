import Foundation
import XCTest
@testable import ControlBoxCore

final class LogitechHIDPP2ClientTests: XCTestCase {
    func testRequestWritesAndCompletesFromMatchingSoftwareID() {
        let recorder = ReportRecorder()
        var reply: Data?
        let client = makeClient(recorder: recorder)

        client.request(featureIndex: 5, function: 1, parameters: [9]) {
            reply = $0
        }

        XCTAssertEqual(recorder.writes.count, 1)
        XCTAssertEqual(Array(recorder.writes[0].prefix(5)), [0x11, 0xFF, 0x05, 0x18, 0x09])
        XCTAssertEqual(client.handle([0x11, 0xFF, 0x05, 0x18, 0xAA]), .matched)
        XCTAssertEqual(reply, Data([0xAA]))
    }

    func testRequestsStaySerialized() {
        let recorder = ReportRecorder()
        var completions: [Int] = []
        let client = makeClient(recorder: recorder)

        client.request(featureIndex: 1, function: 0, parameters: []) { _ in
            completions.append(1)
        }
        client.request(featureIndex: 2, function: 0, parameters: []) { _ in
            completions.append(2)
        }

        XCTAssertEqual(recorder.writes.count, 1)
        XCTAssertEqual(client.handle([0x11, 0xFF, 0x01, 0x08]), .matched)
        XCTAssertEqual(recorder.writes.count, 2)
        XCTAssertEqual(Array(recorder.writes[1].prefix(4)), [0x11, 0xFF, 0x02, 0x09])
        XCTAssertEqual(client.handle([0x11, 0xFF, 0x02, 0x09]), .matched)
        XCTAssertEqual(completions, [1, 2])
    }

    func testFeatureEventFallbackIsPolicyControlled() {
        let mouseRecorder = ReportRecorder()
        var mouseCompleted = false
        let mouse = makeClient(recorder: mouseRecorder, policy: .softwareIDOnly)
        mouse.request(featureIndex: 4, function: 0, parameters: []) { _ in
            mouseCompleted = true
        }
        let event = LogitechHIDPP2Client.IncomingReport(
            featureIndex: 4,
            function: 0,
            softwareID: 0,
            payload: Data([1])
        )
        XCTAssertEqual(mouse.handle([0x11, 0xFF, 0x04, 0x00, 0x01]), .event(event))
        XCTAssertFalse(mouseCompleted)

        let keyboardRecorder = ReportRecorder()
        var keyboardReply: Data?
        let keyboard = makeClient(
            recorder: keyboardRecorder,
            policy: .softwareIDOrFeatureEvent
        )
        keyboard.request(featureIndex: 4, function: 0, parameters: []) {
            keyboardReply = $0
        }
        XCTAssertEqual(keyboard.handle([0x11, 0xFF, 0x04, 0x00, 0x01]), .matched)
        XCTAssertEqual(keyboardReply, Data([1]))
    }

    func testShortReportPolicyWritesLongThenShort() {
        let recorder = ReportRecorder()
        let client = makeClient(recorder: recorder, shortReports: true)

        client.request(featureIndex: 3, function: 2, parameters: [1, 2, 3]) { _ in }

        XCTAssertEqual(recorder.writes.map(\.first), [0x11, 0x10])
        XCTAssertEqual(recorder.writes.map(\.count), [20, 7])
    }

    func testErrorCompletesPendingAndReportsItsOptions() {
        let recorder = ReportRecorder()
        var completionCalled = false
        var errorMetadata: LogitechHIDPP2Client.RequestMetadata?
        let client = makeClient(recorder: recorder)
        client.onError = { errorMetadata = $0 }
        let options = LogitechHIDPP2Client.RequestOptions(
            countsTowardTimeouts: false,
            allowShortReport: false,
            dropsPipeOnError: false
        )

        client.request(featureIndex: 6, function: 1, parameters: [], options: options) {
            XCTAssertNil($0)
            completionCalled = true
        }
        XCTAssertEqual(
            client.handle([0x11, 0xFF, 0x8F, 0x08]),
            .error(
                LogitechHIDPP2Client.RequestMetadata(
                    softwareID: 8,
                    featureIndex: 6,
                    options: options
                )
            )
        )
        XCTAssertTrue(completionCalled)
        XCTAssertEqual(errorMetadata?.options, options)
    }

    func testTimeoutCompletesAndReportsMetadata() {
        let timedOut = expectation(description: "request timeout")
        let recorder = ReportRecorder()
        let client = makeClient(recorder: recorder, timeout: 0.01)
        client.onTimeout = { metadata in
            XCTAssertEqual(metadata.featureIndex, 7)
            timedOut.fulfill()
        }
        client.request(featureIndex: 7, function: 0, parameters: []) {
            XCTAssertNil($0)
        }

        wait(for: [timedOut], timeout: 1)
    }

    private func makeClient(
        recorder: ReportRecorder,
        policy: LogitechHIDPP2Client.ReplyMatchPolicy = .softwareIDOnly,
        shortReports: Bool = false,
        timeout: TimeInterval = 2
    ) -> LogitechHIDPP2Client {
        LogitechHIDPP2Client(
            initialSoftwareID: 0x07,
            replyMatchPolicy: policy,
            timeout: timeout,
            canWrite: { true },
            shortReportsEnabled: { shortReports },
            write: { recorder.writes.append($0) }
        )
    }
}

private final class ReportRecorder {
    var writes: [[UInt8]] = []
}
