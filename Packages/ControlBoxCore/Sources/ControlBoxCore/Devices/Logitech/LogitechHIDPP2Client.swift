import Foundation

/// Serialized HID++ 2.0 request/reply client.
///
/// Device sessions retain transport policy: the writer may target a direct
/// `IOHIDDevice` or a receiver slot, and callbacks decide how a timeout or
/// protocol error affects that family. Call this client from one serial queue
/// (Control Box uses the main queue).
public final class LogitechHIDPP2Client {
    public enum ReplyMatchPolicy: Sendable {
        case softwareIDOnly
        case softwareIDOrFeatureEvent
    }

    public struct RequestOptions: Equatable, Sendable {
        public var countsTowardTimeouts: Bool
        public var allowShortReport: Bool
        public var dropsPipeOnError: Bool

        public init(
            countsTowardTimeouts: Bool = true,
            allowShortReport: Bool = true,
            dropsPipeOnError: Bool = true
        ) {
            self.countsTowardTimeouts = countsTowardTimeouts
            self.allowShortReport = allowShortReport
            self.dropsPipeOnError = dropsPipeOnError
        }
    }

    public struct RequestMetadata: Equatable, Sendable {
        public var softwareID: UInt8
        public var featureIndex: UInt8
        public var options: RequestOptions
    }

    public struct IncomingReport: Equatable, Sendable {
        public var featureIndex: UInt8
        public var function: UInt8
        public var softwareID: UInt8
        public var payload: Data
    }

    public enum ReportResult: Equatable, Sendable {
        case invalid
        case matched
        case error(RequestMetadata?)
        case event(IncomingReport)
    }

    private struct QueuedRequest {
        var featureIndex: UInt8
        var function: UInt8
        var parameters: [UInt8]
        var options: RequestOptions
        var completion: (Data?) -> Void
    }

    private struct PendingRequest {
        var metadata: RequestMetadata
        var completion: (Data?) -> Void
    }

    public var deviceIndex: UInt8 = 0xFF
    public var onReply: (() -> Void)?
    public var onTimeout: ((RequestMetadata) -> Void)?
    public var onError: ((RequestMetadata?) -> Void)?

    private let replyMatchPolicy: ReplyMatchPolicy
    private let timeout: TimeInterval
    private let canWrite: () -> Bool
    private let shortReportsEnabled: () -> Bool
    private let write: ([UInt8]) -> Void
    private var queue: [QueuedRequest] = []
    private var pending: PendingRequest?
    private var generation = 0
    private var softwareID: UInt8

    public init(
        initialSoftwareID: UInt8,
        replyMatchPolicy: ReplyMatchPolicy,
        timeout: TimeInterval = 2,
        canWrite: @escaping () -> Bool,
        shortReportsEnabled: @escaping () -> Bool = { false },
        write: @escaping ([UInt8]) -> Void
    ) {
        softwareID = initialSoftwareID
        self.replyMatchPolicy = replyMatchPolicy
        self.timeout = timeout
        self.canWrite = canWrite
        self.shortReportsEnabled = shortReportsEnabled
        self.write = write
    }

    /// Invalidates queued calls without invoking their completions.
    public func cancelAll() {
        generation += 1
        queue.removeAll()
        pending = nil
    }

    public func request(
        featureIndex: UInt8,
        function: UInt8,
        parameters: [UInt8],
        options: RequestOptions = RequestOptions(),
        completion: @escaping (Data?) -> Void
    ) {
        queue.append(
            QueuedRequest(
                featureIndex: featureIndex,
                function: function,
                parameters: parameters,
                options: options,
                completion: completion
            )
        )
        pump()
    }

    /// Sends a long report outside the request queue, used while restoring
    /// native reporting during teardown.
    public func send(featureIndex: UInt8, function: UInt8, parameters: [UInt8]) {
        guard canWrite() else { return }
        softwareID = LogitechHIDPP2.nextSoftwareID(after: softwareID)
        write(
            LogitechHIDPP2.longReport(
                deviceIndex: deviceIndex,
                featureIndex: featureIndex,
                function: function,
                softwareID: softwareID,
                parameters: parameters
            )
        )
    }

    @discardableResult
    public func handle(_ report: [UInt8]) -> ReportResult {
        guard report.count >= 4,
              report[0] == LogitechHIDPP2.shortReportID
                || report[0] == LogitechHIDPP2.longReportID
        else {
            return .invalid
        }

        if report[2] == 0x8F {
            let metadata = pending?.metadata
            if pending != nil {
                finishPending(with: nil)
            }
            onError?(metadata)
            return .error(metadata)
        }

        let incoming = IncomingReport(
            featureIndex: report[2],
            function: report[3] >> 4,
            softwareID: report[3] & 0x0F,
            payload: Data(report.dropFirst(4))
        )
        if let pending, matches(incoming, pending.metadata) {
            onReply?()
            finishPending(with: incoming.payload)
            return .matched
        }
        return .event(incoming)
    }

    private func matches(_ report: IncomingReport, _ request: RequestMetadata) -> Bool {
        if report.softwareID != 0, report.softwareID == request.softwareID {
            return true
        }
        return replyMatchPolicy == .softwareIDOrFeatureEvent
            && report.softwareID == 0
            && report.featureIndex == request.featureIndex
    }

    private func pump() {
        guard pending == nil, canWrite(), let call = queue.first else { return }
        softwareID = LogitechHIDPP2.nextSoftwareID(after: softwareID)
        let metadata = RequestMetadata(
            softwareID: softwareID,
            featureIndex: call.featureIndex,
            options: call.options
        )
        pending = PendingRequest(metadata: metadata, completion: call.completion)
        write(
            LogitechHIDPP2.longReport(
                deviceIndex: deviceIndex,
                featureIndex: call.featureIndex,
                function: call.function,
                softwareID: softwareID,
                parameters: call.parameters
            )
        )
        if shortReportsEnabled(),
           call.options.allowShortReport,
           call.parameters.count <= LogitechHIDPP2.shortParameterCount {
            write(
                LogitechHIDPP2.shortReport(
                    deviceIndex: deviceIndex,
                    featureIndex: call.featureIndex,
                    function: call.function,
                    softwareID: softwareID,
                    parameters: call.parameters
                )
            )
        }

        let requestGeneration = generation
        let requestSoftwareID = softwareID
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
            guard let self,
                  self.generation == requestGeneration,
                  let pending = self.pending,
                  pending.metadata.softwareID == requestSoftwareID
            else {
                return
            }
            let metadata = pending.metadata
            self.finishPending(with: nil)
            self.onTimeout?(metadata)
        }
    }

    private func finishPending(with data: Data?) {
        guard let pending else { return }
        self.pending = nil
        if !queue.isEmpty {
            queue.removeFirst()
        }
        pending.completion(data)
        pump()
    }
}
